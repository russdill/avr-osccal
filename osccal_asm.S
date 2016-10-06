/*
 * Copyright (C) 2016 Russ Dill <Russ.Dill@gmail.com>
 *
 * BSD-2-Clause
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
 * IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#define __SFR_OFFSET 0

#include <avr/io.h>

/*Count how many CPU cycles pass during FREQ_CYCLES of the stimulus clock. */
.global osccal_loop
osccal_loop:
	/* Setup loop counter */
	ldi r18, FREQ_CYCLES
	clr r25

	/* Configure timer */
	out TCNT0, r25		/* Start from count 0 */
	ldi r24, _BV(TOV0)	/* Clear overflow status */

	/* Wait for clock falling edge */
1:	sbis PINB, MOSI
	rjmp 1b
1:	sbic PINB, MOSI
	rjmp 1b			/* 1 (when skipped) */

	/* Move these inits here to delay 2 cycles to match with end */
	out TIFR, r24
	ldi r24, _BV(CS00)	/* No prescaler */

	/* Start timer */
	out TCCR0B, r24		/* 1 */

timing_loop:
	/* Check overflow */
	in r24, TIFR		/* 1 */
	sbrc r24, TOV0		/* 1 */
	inc r25			/* 1 */
	out TIFR, r24		/* 1 */

	/* Wait for edge (rising) */
1:	sbis PINB, MOSI		/* 1 */
	rjmp 1b			/* 1 */

	/* Check overflow */
	in r24, TIFR		/* 1 */
	sbrc r24, TOV0		/* 1 */
	inc r25			/* 1 */
	out TIFR, r24		/* 1 */

	/* Wait for edge (falling) */
1:	sbic PINB, MOSI		/* 1 */
	rjmp 1b			/* 1 */

	dec r18			/* 1 */
	brne timing_loop	/* 2 (1 if false) */

	/* Stop timer (r18 is zero) */
	out TCCR0B, r18		/* 1 */

	/* Check for final overflow */
	in r24, TIFR		/* 1 */
	sbrc r24, TOV0
	inc r25

	in r24, TCNT0

	/* Returns 16 bit value in r24/r25 */
	ret

/*
 * Send the success signal, 8 transitions on the falling edge of the stimulus
 * clock.
 */
.global signal_done
signal_done:
	ldi r18, 8
	/* Wait for falling edge */
1:	sbis PINB, MOSI
	rjmp 1b
2:	sbic PINB, MOSI
	rjmp 2b

	/* Toggle MISO */
	sbi PINB, MISO

	dec r18
	brne 1b

	ret
