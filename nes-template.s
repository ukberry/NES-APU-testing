; I have created this template for NES games based on the content
; at NesDev and Classic Game Programming for the NES by Tony Cruise

.segment "HEADER"

INES_MIRROR = 0 ; 0: Horizontal mirroring, 1: Vertical mirroring
INES_BBRAM   = 0 ; BBRAM (usually at $6000)
INES_MAPPER = 0 ; Mapper ID byte

.byte 'N', 'E', 'S', $1A ; NES cartridge Magic number
.byte $02 ; Size of PRG ROM in 16 KB units
.byte $01 ; Size of CHR ROM in 8 KB units

; Name table layout, BBRAM, and Mapper number
.byte INES_MIRROR | (INES_BBRAM << 1) | ( INES_MAPPER & $f0)
.byte $0 ; This is the upper nibble of the mapper number

; Remaining header bytes padded
.byte $0, $0, $0, $0, $0, $0, $0, $0 ; Padding Bytes

.segment "VECTORS"
.word nmi
.word reset
.word irq

; PPU Registers
PPU_CONTROL = $2000         ; PPU Control Register 1 (Write)
PPU_MASK = $2001            ; PPU Control Register 2 (Write)
PPU_STATUS = $2002          ; PPU Status Register (Read)
PPU_SPRRAM_ADDRESS = $2003  ; PPU SPR-RAM Address Register (Write)
PPU_SPRRAM_IO = $2004       ; PPU SPR-RAM I/O Register (Write)
PPU_VRAM_ADDRESS1 = $2005   ; PPU VRAM Address Register 1 (Write)
PPU_VRAM_ADDRESS2 = $2006   ; PPU VRAM Address Register 2 (Write)
PPU_VRAM_IO = $2007         ; VRAM I/O Register (Read/Write)
SPRITE_DMA = $4014          ; Sprite DMA Register

; Define APU Registers
APU_DM_CONTROL = $4010      ; APU Delta Modulation Control Register (Write)
APU_CLOCK = $4015           ; APU Sound/Vertical Clock Signal Register (Read/Write)
APU_FRAME_COUNTER = $4017   ; (Write only)

; Joypad registers
JOYPAD_STROBE = $4016           ; Set joypad polling strobe (Write)
JOYPAD1 = JOYPAD_STROBE         ; Joypad 1 (Read data)
JOYPAD2 = APU_FRAME_COUNTER     ; Joypad 2 (Read data)

; Gamepad bit values
PAD_A      = $01
PAD_B      = $02
PAD_SELECT = $04
PAD_START  = $08
PAD_U      = $10
PAD_D      = $20
PAD_L      = $40
PAD_R      = $80

.segment "ZEROPAGE"

nmi_ready:		.res 1 ; set to 1 to push a PPU frame update, 
					   ;        2 to turn rendering off next NMI
joypad1:		.res 1 ; Joypad 1's button state.
joypad2:		.res 1 ; Joypad 2's button state.

.segment "CODE"
; First start with the highly recommended ppu functions.
; Turns rendering on and transfers sprites to VRAM on the next NMI/VBlank
.proc ppu_update
	lda #1
	sta nmi_ready
	loop:
		lda nmi_ready
		bne loop
	rts
.endproc

; Will set rendering off on the next NMI/VBlank
.proc ppu_off
	lda #2
	sta nmi_ready
	loop:
		lda nmi_ready
		bne loop
	rts
.endproc

.proc reset
	sei			; Set interrupt disable bit
    cld         ; Clear decimal mode bit (not really necessary for a real NES)

	ldx #$40
	stx APU_FRAME_COUNTER   ; disable APU frame IRQ

	ldx #$FF
	txs			; Stack pointer now $01ff
	inx ; X is now $00
	stx PPU_CONTROL
	stx PPU_MASK
	stx APU_DM_CONTROL

	; wait for first vBlank
	bit PPU_STATUS
@wait_vblank:
	bit PPU_STATUS
	bpl @wait_vblank

	; clear all RAM to 0
	txa ; A now also $00
@clear_mem:
	sta $0000,x
	sta $0100,x
	sta $0200,x
	sta $0300,x
	sta $0400,x
	sta $0500,x
	sta $0600,x
	sta $0700,x
	inx
	bne @clear_mem

	; place all sprites offscreen at Y=255 using first
	; attribute bytes of 4 (skip 4 bytes for next sprite).
	lda #255
	ldx #0
clear_oam:
	sta oam,x ; Each sprite has 4 bytes of attributes
	inx
	inx
	inx
	inx ; Offset now skipped 4 bytes, pointint at next sprite
	bne clear_oam ; or zero status bit is set and we continue

; After next VBlank we will be ready
@wait_vblank2:
	bit PPU_STATUS
	bpl @wait_vblank2
	
	; NES is initialized and ready to begin
	; - enable the NMI for graphical updates and jump to our main program
	lda #%10001000
	sta PPU_CONTROL
	jmp main
.endproc

; This will populate the A register with the JOYPAD1 button states
.proc gamepad_poll
	; strobe the gamepad to latch current button state
	lda #1
	sta JOYPAD_STROBE
	lda #0
	sta JOYPAD_STROBE
	; Each button state requires 8 single byte reads
	ldx #8
@loop:
	pha
	lda JOYPAD1
	and #%00000011
	cmp #%00000001
	pla
	; rotate carry into gamepad variable
	ror
	dex
	bne @loop
	sta joypad1
	ldx #8 ; Now for Joypad 2
@loop2:
	pha
	lda JOYPAD2
	and #%00000011
	cmp #%00000001
	pla
	; rotate carry into gamepad variable
	ror
	dex
	bne @loop2
	sta joypad2
	rts
.endproc
