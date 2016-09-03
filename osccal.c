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

#include <stdbool.h>

#include <avr/io.h>
#include <avr/eeprom.h>
#include <avr/wdt.h>
#include <avr/interrupt.h>

#include "osccal_asm.h"

/* Normal rounding */
#define TARGET_TICKS	((F_CPU * FREQ_CYCLES + INPUT_FREQ / 2) / INPUT_FREQ)

/* 1% precision, round up */
#define TOLERANCE_TICKS	(1 + (TARGET_TICKS - 1) / 100)

static bool calibrate_range(unsigned char osccal_min, unsigned char osccal_max)
{
	unsigned char step;
	unsigned char osccal;
	unsigned char curr;
	unsigned int ticks;
	unsigned int deviation;
	unsigned int min_deviation;
	unsigned char best;

	/* Binary search for ideal OSCCAL */
	step = (osccal_max - osccal_min + 1) / 2;
	osccal = osccal_min + step;

	wdt_reset();
	for (;;) {
		curr = OSCCAL;
		/* Don't adjust OSCCAL too much at once */
		while (curr != osccal) {
			unsigned char diff = osccal - curr;
			if (curr > osccal)
				diff = -diff;
			if (diff > OSCCAL_MAXD) {
				if (curr > osccal)
					curr -= OSCCAL_MAXD;
				else
					curr += OSCCAL_MAXD;
			} else
				curr = osccal;
			OSCCAL = curr;
		}

		ticks = osccal_loop();

		if (ticks == TARGET_TICKS)
			return true;

		step /= 2;
		if (!step)
			break;

		if (ticks < TARGET_TICKS)
			osccal += step;
		else
			osccal -= step;
	}

	/* Try two below, two above (clip to osccal_min/max) */
	if (osccal > osccal_min + 2)
		osccal_min = osccal - 2;
	if (osccal < osccal_max - 2)
		osccal_max = osccal + 2;

	best = osccal;
	min_deviation = 0xffff;
	wdt_reset();
	for (osccal = osccal_min; osccal <= osccal_max; osccal++) {
		OSCCAL = osccal;
		ticks = osccal_loop();
		if (ticks == TARGET_TICKS)
			return true;
		if (ticks < TARGET_TICKS)
			deviation = TARGET_TICKS - ticks;
		else
			deviation = ticks - TARGET_TICKS;
		if (deviation <= min_deviation) {
			min_deviation = deviation;
			best = osccal;
		}
	}

	OSCCAL = best;
	return min_deviation < TOLERANCE_TICKS;
}

int main(void)
{
	/* Don't process interrupts */
	cli();

	/* Configure pins, MISO is output, MOSI has pull-up */
	DDRB |= _BV(MISO);
	PORTB |= _BV(MOSI);

	/* Ready signal */
	PORTB |= _BV(MISO);

	/* Wait for first rising clock edge */
	while (PINB & _BV(MOSI))
		wdt_reset();
	while (!(PINB & _BV(MOSI)))
		wdt_reset();

#if (OSC_VER == 1) || (OSC_VER == 2) || (OSC_VER == 3)
	if (!calibrate_range(0, 0xff)) {
#elif OSC_VER == 4
	if (!calibrate_range(0, 0x7f)) {
#elif OSC_VER == 5
	if (!calibrate_range(0, 0x7f) && !calibrate_range(0x80, 0xff)) {
#else
#error "Invalid OSC_VER"
#endif
		/* Calibration failed, clear MISO pin */
		PINB |= _BV(MISO);
	} else {
		/* Calibration success, store new value */
		wdt_reset();
		eeprom_update_byte(0x00, OSCCAL);

		/* Complete, signal by toggling MISO pin */
		wdt_reset();
		signal_done();
	}

	for (;;)
		wdt_reset();
	return 0;
}
