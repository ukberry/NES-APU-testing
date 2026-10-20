
.include "nes-template.s"

;*****************************************************************
; Import both the background and sprite character sets
;*****************************************************************

.segment "TILES"
.incbin "example.chr"

;*****************************************************************
; 6502 Zero Page Memory (256 bytes)
;*****************************************************************

.segment "ZEROPAGE"

gamepad:		.res 1 ; stores the current gamepad values

d_x:			.res 1 ; x velocity of ball
d_y:			.res 1 ; y velocity of ball
bgm_track: 		.res 1 ; 

;*****************************************************************
; Sprite OAM Data area - copied to VRAM in NMI routine
;*****************************************************************

.segment "OAM"
oam: .res 256	; sprite OAM data

;*****************************************************************
; Remainder of normal RAM area
;*****************************************************************

.segment "BSS"
palette: .res 32 ; current palette buffer


;*****************************************************************
; NMI Routine - called every vBlank
;*****************************************************************

.segment "CODE"
.proc nmi
	; save registers
	pha
	txa
	pha
	tya
	pha

	lda nmi_ready
	bne :+ ; nmi_ready == 0 not ready to update PPU
		jmp ppu_update_end
	:
	cmp #2 ; nmi_ready == 2 turns rendering off
	bne cont_render
		lda #%00000000
		sta PPU_MASK
		ldx #0
		stx nmi_ready
		jmp ppu_update_end
cont_render:

	; transfer sprite OAM data using DMA
	ldx #0
	stx PPU_SPRRAM_ADDRESS
	lda #>oam
	sta SPRITE_DMA

	lda #$23
	sta PPU_VRAM_ADDRESS2
	lda #$CA
	sta PPU_VRAM_ADDRESS2
	lda #%00001000
	sta PPU_VRAM_IO
	lda #%00001101
	sta PPU_VRAM_IO

	; transfer current palette to PPU
	lda #%10001000 ; set horizontal nametable increment
	sta PPU_CONTROL 
	lda PPU_STATUS
	lda #$3F ; set PPU address to $3F00
	sta PPU_VRAM_ADDRESS2
	stx PPU_VRAM_ADDRESS2
	ldx #0 ; transfer the 32 bytes to VRAM
loop:
	lda palette, x
	sta PPU_VRAM_IO
	inx
	cpx #32
	bcc loop

	; enable rendering
	lda #%00011110
	sta PPU_MASK

	; flag PPU update complete
	ldx #0
	stx nmi_ready
ppu_update_end:

	; restore registers and return
	pla
	tay
	pla
	tax
	pla
	rti
.endproc

;*****************************************************************
; IRQ Clock Interrupt Routine
;*****************************************************************

.segment "CODE"
irq:
	rti

;*****************************************************************
; Main application logic section includes the game loop
;*****************************************************************
 .segment "CODE"
 .proc main
 	; main application - rendering is currently off

 	; initialize palette table
 	ldx #0
paletteloop:
	lda default_palette, x
	sta palette, x
	inx
	cpx #32
	bcc paletteloop

 	; clear 1st name table
 	jsr clear_nametable

 	; draw some text on the screen
 	lda PPU_STATUS ; reset address latch
 	lda #$20 ; set PPU address to $208A (Row = 4, Column = 10)
 	sta PPU_VRAM_ADDRESS2
 	lda #$8A
 	sta PPU_VRAM_ADDRESS2

 	ldx #0
textloop:
	lda welcome_txt, x
	sta PPU_VRAM_IO
	inx
	cmp #0
	beq :+
	jmp textloop
 	:

 	; place our bat sprite on the screen
 	lda #180
 	sta oam ; set Y
 	lda #120
 	sta oam + 3 ; set X
 	lda #1
 	sta oam + 1 ; set pattern
 	lda #2
 	sta oam + 2 ; set attributes
 	; place our ball sprite on the screen
 	lda #124
 	sta oam + (1 * 4) ; set Y
 	sta oam + (1 * 4) + 3 ; set X
 	lda #2
 	sta oam + (1 * 4) + 1 ; set patter + (1 * 4)n
 	lda #1
 	sta oam + (1 * 4) + 2 ; set atttibutes
 	; set the ball velocity
 	lda #1
 	sta d_x
 	sta d_y

 	; get the screen to render
 	jsr ppu_update

 mainloop:
 	; skip reading controls if and change has not been drawn
 	lda nmi_ready
 	cmp #0
 	bne mainloop
 	; read the gamepad
 	jsr gamepad_poll
 	; now move the bat if left or right pressed
 	lda joypad1
 	and #PAD_L
 	beq NOT_GAMEPAD_LEFT
 		; gamepad has been pressed left
 		lda oam + 3 ; get current X
 		cmp #0
 		beq NOT_GAMEPAD_LEFT
 		sec
 		sbc #1
 		sta oam + 3 ; change X to the left
 NOT_GAMEPAD_LEFT:
 	lda joypad1
 	and #PAD_R
 	beq NOT_GAMEPAD_RIGHT
 		; gamepad has been pressed right
 		lda oam + 3 ; get current X
 		cmp #248
 		beq NOT_GAMEPAD_RIGHT
 		clc
 		adc #1
 		sta oam + 3 ; change X to the left
 NOT_GAMEPAD_RIGHT:
	lda joypad2
	and #PAD_U
	beq NOT_GAMEPAD_UP
		lda oam
		cmp #0
		beq NOT_GAMEPAD_UP
			sec
			sbc #1
			sta oam
 NOT_GAMEPAD_UP:
	lda joypad2
	and #PAD_D
	beq NOT_GAMEPAD_DOWN
		lda oam
		cmp #210
		beq NOT_GAMEPAD_DOWN
			clc
			adc #1
			sta oam
 
 NOT_GAMEPAD_DOWN:
 	; now move our ball
 	lda oam + (1 * 4) + 0 ; get the current Y
	clc
	adc d_y ; add the Y velocity
 	sta oam + (1 * 4) + 0 ; write the change
 	cmp #0 ; have we hit the top border
 	bne NOT_HITTOP
 		lda #1 ; reverse direction
 		sta d_y
 NOT_HITTOP:
 	lda oam + (1 * 4) + 0
 	cmp #210 ; have we hit the bottom border
 	bne NOT_HITBOTTOM
 		lda #$FF ; reverse direction (-1)
 		sta d_y
 NOT_HITBOTTOM:
 	lda oam + (1 * 4) + 3 ; get the current x
 	clc
 	adc d_x	; add the X velocity
 	sta oam + (1 * 4) + 3
 	cmp #0 ; have we hit the left border
 	bne NOT_HITLEFT
 		lda #1 ; reverse direction
 		sta d_x
 NOT_HITLEFT:
 	lda oam + (1 * 4) + 3
 	cmp #248 ; have we hot the right border
 	bne NOT_HITRIGHT
 		lda #$FF ; reverse direction (-1)
 		sta d_x
 NOT_HITRIGHT:

 	; ensure our changes are rendered
 	lda #1
 	sta nmi_ready
 	jmp mainloop
.endproc

.segment "CODE"
.proc clear_nametable
 	lda PPU_STATUS ; reset address latch
 	lda #$20 ; set PPU address to $2000
 	sta PPU_VRAM_ADDRESS2
 	lda #$00
 	sta PPU_VRAM_ADDRESS2

 	; empty nametable
 	lda #0
 	ldy #30 ; clear 30 rows
 	rowloop:
 		ldx #32 ; 32 columns
 		columnloop:
 			sta PPU_VRAM_IO
 			dex
 			bne columnloop
 		dey
 		bne rowloop

 	; empty attribute table
 	ldx #64 ; attribute table is 64 bytes
 	loop:
 		sta PPU_VRAM_IO
 		dex
 		bne loop
 	rts
 .endproc

;*****************************************************************
; Our default palette table 16 entries for tiles and 16 entries for sprites
;*****************************************************************

.segment "RODATA"
default_palette:
.byte $0F,$15,$26,$37 ; bg0 purple/pink
.byte $0F,$09,$19,$29 ; bg1 green
.byte $0F,$01,$11,$21 ; bg2 blue
.byte $0F,$00,$10,$30 ; bg3 greyscale
.byte $0F,$18,$28,$38 ; sp0 yellow
.byte $0F,$14,$24,$34 ; sp1 purple
.byte $0F,$1B,$2B,$3B ; sp2 teal
.byte $0F,$12,$22,$32 ; sp3 marine

welcome_txt:
.byte 'W','E','L','C', 'O', 'M', 'E', ' ', 'T', 'O', ' ', 'S', 'P', 'A', 'C', 'E', 0
