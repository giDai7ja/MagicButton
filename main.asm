;
; TouchT4.asm
;
; Created: 01.02.2018 17:32:58
; Author : Poppy
;

.device	ATtiny4
.include "tn4def.inc"

.def	TMP = r16			; Рабочий регистр
.def	TMPL = r17			; Рабочий регистр
.def	COUNT = r18			; Счётчик циклов WDT
.def	FLAG = r19			; Регистр флагов
.def	PWML = r20			; Текущее значение ШИМ
.def	PWMH = r21
.def	SPWML = r22			; Интенсивность зрительного ощущения яркости
.def	SPWMH = r23
.def	TMPH = r24

#define mc16uL XL			;multiplicand low byte
#define mc16uH XH			;multiplicand high byte
#define	mp16uL YL			;multiplier low byte
#define	mp16uH YH			;multiplier high byte
#define	m16u0 YL			;result byte 0 (LSB)
#define	m16u1 YH			;result byte 1
.def	m16u2	=r25		;result byte 2
#define	m16u3 ZL			;result byte 3 (MSB)
#define	mcnt16u ZH			;loop counter


; Биты флагового регистра
.equ	ON_OFF = 0			; Состояние светильника (0-выключен, 1-включен)
.equ	UP_DOWN = 1			; Направление изменения яркости
.equ	WDT_F = 2			; Флаг WDT
.equ	FFADE = 3			; Нужно изменять яркость
.equ	BORDER = 4			; Достигнута границы регулировки 
.equ	BORDER_OK = 5		; Вибра сработала
 
.equ	PIN_SENSOR = PINB0	; Вход сенсора
.equ	PIN_PWM = PINB1		; Выход ШИМ
.equ	PIN_V = PINB2		; Выход на вибру
.equ	DREBEZG = 3			; Число циклов WDT для устранения помех и дребезга
.equ	LONG_PRESS = 28		; Число циклов WDT для длинного нажатия
.equ	STEP_PWM = 134		; Шаг регулировки ШИМ
.equ	MIN_SPWM = 0x2000	; Минимальное значение яркости

.cseg

.org 0
; Таблица векторов прерываний
	rjmp	RESET		; RESET			External Pin, Power-on Reset, VLM Reset and Watchdog Reset
	reti				; INT0			External Interrupt Request 0
	reti				; PCINT0		Pin Change Interrupt Request 0
	reti				; TIM0_CAPT		Timer/Counter0 Capture
;.org OVF0addr
	rjmp	TIM0_OVF	; TIM0_OVF		Timer/Counter0 Overflow
	reti				; TIM0_COMPA	Timer/Counter0 Compare Match A
	reti				; TIM0_COMPB	Timer/Counter0 Compare Match B
	reti				; ANA_COMP		Analog Comparator
	rjmp	WDT			; WDT			Watchdog Time-out Interrupt
	reti				; VLM			VCC Voltage Level Monitor
#if defined(__ATtiny5__) || defined(__ATtiny10__)
	reti				; ADC			ADC Conversion Complete (The ADC is only available in ATtiny5/10)
#endif

.org	INT_VECTORS_SIZE

RESET:		
; Запрещаем прерывания
	cli

; Настраиваем тактирование (выключаем предделитель на 8)
	ldi		TMP, 0xD8
	out		CCP, TMP
	clr		TMP
	out		CLKPSR, TMP

; Установить указатель стэка в конец оперативной памяти
	ldi		TMP, low(RAMEND)
	out		SPL, TMP	
	ldi		TMP, high(RAMEND)
	out		SPH, TMP

; Настраиваем Watchdog Timer (32ms)
	ldi		TMP, 0xD8
	out		CCP, TMP
	ldi		TMP, (1<<WDIE)|(1<<WDP0)
	out		WDTCSR, TMP

; Разрешаем прерывания
	sei

; Выключаем лишнюю переферию (для ATtiny5/10)
#if defined(__ATtiny5__) || defined(__ATtiny10__)
	ldi		TMP, (1<<PRADC)
	out		PRR, TMP
#endif

; Настраиваем порт на выход
	ldi		TMP, (1<<PIN_PWM)|(1<<PIN_V)
	out		DDRB, TMP
	cbi		PORTB, PIN_PWM
	cbi		PORTB, PIN_V

; Начальные значения
	ser		PWMH
	ser		PWML
	ser		SPWML
	ser		SPWMH
	out		OCR0AH, SPWMH
	out		OCR0AL, SPWML
	ldi		COUNT, 0x00
	ldi		FLAG, 0x00

; Основная программа
MAIN:
	sbis	PINB, PIN_SENSOR
	rjmp	UN_PRESS
	cpi		COUNT, LONG_PRESS
	brge	FADE
	inc		COUNT
	rjmp	END

; Меняем яркость
FADE:
; Если свет выключен, то включаем на полную
	sbrc	FLAG, ON_OFF
	rjmp	FADE_ON

	ser		SPWMH
	ser		SPWML

	sbr		FLAG, (1<<UP_DOWN)|(1<<ON_OFF)
	rcall	TIMER_ON
	rjmp	END

FADE_ON:
	sbr		FLAG, (1<<FFADE)
	rjmp	END

UN_PRESS:
; Проверка на слишком короткое нажатие
	cpi		COUNT, DREBEZG
	brlt	END_MAIN

; Проверка на короткое нажатие
	cpi		COUNT, LONG_PRESS 
	brge	END_FADE

; Нажатие было короткое
	sbrc	FLAG, ON_OFF
	rjmp	SHORT_OFF

; Включить свет
	rcall	TIMER_ON
	sbr		FLAG, (1<<ON_OFF)
	rjmp	END_MAIN

; Выключить свет
SHORT_OFF:
	rcall	TIMER_OFF
	cbr		FLAG, (1<<ON_OFF)
	rjmp	END_MAIN

; Меняем направление изменения яркости, если свет включен
END_FADE:
	cbr		FLAG, (1<<FFADE)
	ldi		TMP, (1<<UP_DOWN)
	eor		FLAG , TMP	

; Конец главного цикла
END_MAIN:
	clr		COUNT
	cbr		FLAG, (1<<BORDER)|(1<<BORDER_OK)
END:
    rcall	IDLE
	rjmp	MAIN



; *******************************************
; *-------------- ПОДПРОГРАММЫ -------------*
; *******************************************

; Уход в спячку и выход только по WDT
IDLE:
	ldi		TMP, (1<<SE)
	sbrs	FLAG, ON_OFF
	sbr		TMP, (1<<SM1)
	out		SMCR, TMP
	sleep
	sbrs	FLAG, WDT_F
	rjmp	IDLE
	cbr		FLAG, (1<<WDT_F)
	ret

; Запуск таймера и ШИМ
TIMER_ON:
; Настраиваем таймер (clk, 16 бит, Fast PWM, TOP OCR0A)
	out		OCR0BH, PWMH
	out		OCR0BL, PWML
	clr		TMP
	out		TCNT0H, TMP
	out		TCNT0L, TMP
	ldi		TMP, (1<<COM0B1)|(1<<WGM00)|(1<<WGM01)
	out		TCCR0A, TMP
	ldi		TMP, (1<<CS00)|(1<<WGM02)|(1<<WGM03)
	out		TCCR0B, TMP
	ldi		TMP, (1<<TOIE0)
	out		TIMSK0 , TMP
	ret

; Остановка таймера
TIMER_OFF:
	clr		TMP
	out		TCCR0B, TMP
	out		TCCR0A, TMP
	out		TIMSK0 , TMP
	cbi		PORTB, PIN_PWM
	ret



; *******************************************
; *---------- ОБРАБОТКА ПРЕРЫВАНИЙ ---------*
; *******************************************

; Прерывание по переполнению таймера
TIM0_OVF:
; Сохраняем SREG
	in		TMPL, SREG
	push	TMPL

; Сразу меняем скважность
	out		OCR0BH, PWMH
	out		OCR0BL, PWML

; Проверяем нужно ли менять яркость
	sbrs	FLAG, FFADE
	rjmp	TIM0_OVF_END

; В какую сторону менять яркость?
	sbrc	FLAG, UP_DOWN
	rjmp	FADE_UP

; Уменьшаем яркость
	ldi		TMPL, low(STEP_PWM)
	ldi		TMPH, high(STEP_PWM)
	sub		SPWML, TMPL
	sbc		SPWMH, TMPH
	ldi		TMPL, low(MIN_SPWM)
	ldi		TMPH, high(MIN_SPWM)
	cp		SPWML, TMPL
	cpc		SPWMH, TMPH
	brcc	NEW_PWM
	mov		SPWML, TMPL
	mov		SPWMH, TMPH
	sbr		FLAG, (1<<BORDER)
	rjmp	NEW_PWM
	
; Увеличиваем яркость
FADE_UP:
	ldi		TMPL, low(STEP_PWM)
	ldi		TMPH, high(STEP_PWM)
	add		SPWML, TMPL
	adc		SPWMH, TMPH
	brcc	NEW_PWM
	ser		SPWMH
	ser		SPWML
	ser		PWML
	ser		PWMH
	sbr		FLAG, (1<<BORDER)
	rjmp	TIM0_OVF_END

NEW_PWM:	
; Вычисляем новое значение ШИМ
	mov		mc16uL, SPWML
	mov		mc16uH, SPWMH
	mov		mp16uL, SPWML
	mov		mp16uH, SPWMH
	rcall	mpy16u
	mov		mc16uL, SPWML
	mov		mc16uH, SPWMH
	mov		mp16uL, m16u2
	mov		mp16uH, m16u3
	rcall	mpy16u
	mov		PWML, m16u2
	mov		PWMH, m16u3

TIM0_OVF_END:
; Возвращаем SREG
	pop		TMPL
	out		SREG, TMPL
	reti

; Прерывание Watchdog таймера
WDT:
	cbi		PORTB, PIN_V
	sbrs	FLAG, BORDER
	rjmp	WDTI_END
	sbrc	FLAG, BORDER_OK
	rjmp	WDTI_END
	sbi		PORTB, PIN_V
	sbr		FLAG, (1<<BORDER_OK)

WDTI_END:
	sbr		FLAG, (1<<WDT_F)
	reti

; AVR(200)
mpy16u:
	clr		m16u3
	clr		m16u2
	ldi		mcnt16u, 16
	lsr		mp16uH
	ror		mp16uL

m16u_1:
	brcc	noad8
	add		m16u2, mc16uL
	adc		m16u3, mc16uH
noad8:
	ror		m16u3
	ror		m16u2
	ror		m16u1
	ror		m16u0
	dec		mcnt16u
	brne	m16u_1
	ret
