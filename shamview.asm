; SAM HAM viewer v1.0
;
; http://simonowen.com/sam/shamview/
;
; Displays SAM Coupé images with increased colour count using a
; width-dependent split of static and dynamic palette colours.
;
; Use shamconv.py to convert images to .sham format

palette:    equ &f8             ; palette port (CLUT)
status:     equ &f9             ; interrupt status port
line:       equ &f9             ; line interrupt position
lmpr:       equ &fa             ; Low Memory Page Register
hmpr:       equ &fb             ; High Memory Page Register
vmpr:       equ &fc             ; Video Memory Page Register
border:     equ &fe
keyboard:   equ &fe

rom0_off:   equ %00100000       ; ROM0 off bit in LMPR
mode_4:     equ %01100000       ; mode 4 bits in VMPR

base:       equ  &f000

            autoexec
            org  base
            dump $
start:
            di

            in  a,(lmpr)        ; current low page
            ex  af,af'          ; save for later

            in  a,(vmpr)        ; current display settings
            and %00011111       ; keep page bits
            or  rom0_off        ; ROM 0 off
            out (lmpr),a        ; page into low memory

            ld  hl,start
            ld  de,start - &8000
            ld  bc,end-start
            ldir                ; copy viewer to display pages

            and %00011111       ; just page bits
            out (hmpr),a        ; switch code under our feet

            ld  (old_sp+1),sp
            ld  sp,new_stack    ; new stack after viewer

            ex  af,af'
            push af             ; save original lmpr
            in  a,(vmpr)
            push af             ; save original vmpr
            ex  af,af'
            or  mode_4          ; mode 4
            out (vmpr),a        ; activate display

            ld  a,&fe
            ld  hl,&fd00
imtab_lp:   ld  (hl),a          ; fill IM 2 vector table
            inc l
            jr  nz,imtab_lp
            inc h
            ld  (hl),a          ; final entry

            ld  a,&fd
            ld  i,a
            im  2               ; activate new IM handler

first_img:  ld  a,3+rom0_off    ; start of sample screens
            out (lmpr),a        ; page in low memory
            ld  hl,0            ; first image data pointer
            ld  (img_ptr),hl

next_img:   di
            ld  hl,(img_ptr)    ; current image
            call prepare_img    ; prepare for viewing
            ld  (img_ptr),hl    ; save for next image
            ei
            jr  nz,first_img    ; loop sequence after final image

wait_nokey: halt

            xor a
            in  a,(keyboard)
            cpl
            and %00011111
            jr  nz,wait_nokey   ; wait for all keys released

wait_key:   halt

            xor a
            in  a,(keyboard)
            cpl
            and %00011111
            jr  z,wait_key      ; wait for a key press

            jr  next_img        ; move to next image
                                ; ... or potential return to BASIC
exit:       pop af
            out (vmpr),a        ; restore display
            pop af
            out (lmpr),a        ; restore low memory

old_sp:     ld  sp,0            ; restore stack
            im  1               ; restore IM
            ret

img_ptr:    dw 0                ; pointer to image data


; Expand image data and prepare for viewing
prepare_img:
            xor a
            ld  bc,&0ff8
black_lp:   out (c),a           ; set palette to all black
            djnz black_lp
            out (c),a

            ld  a,(hl)          ; S
            inc hl
            cp  "S"
            ret nz              ; fail non-image data
            ld  a,(hl)          ; H
            inc hl
            cp  "H"
            ret nz              ; fail non-image data

            ld  a,(hl)          ; file format version version (0)
            inc hl
            and a
            ret nz

            ld  c,(hl)          ; dynamic colours per line
            inc hl

            push bc

            ld  a,11            ; max dynamic palette size for viewer
            sub c
            add a,a             ; 2 extra iterations per skipped OUTI
            inc a               ; base counter of 1
            ld  (p_ld_de+2),a

            ld  a,15            ; maximum delay for start offset
            sub c               ; 1 less iteration per skipped OUTI
            ld  (p_ld_b+1),a

            ld  a,22            ; max JR offset
            sub c               ; less 2 for each OUTI (colour)
            sub c
            ld  (p_jr+1),a

            ld  a,(hl)          ; border index
            inc hl
            out (border),a

            ld  b,a             ; low nibble
            add a,a
            add a,a
            add a,a
            add a,a             ; now high nibble
            or  b               ; combined fill byte to match border colour

            ld  de,&8000        ; screen at &8000
            ld  b,&60
fill_lp:    ld  (de),a          ; fill display
            inc e
            jr  nz,fill_lp
            inc d
            djnz fill_lp

            ld  c,(hl)          ; bytes per line (width/2)
            inc hl
            ld  a,(hl)          ; image height
            inc hl
            push af
            inc hl              ; (reserved)

            exx
            ld  b,a             ; line counter for copy loop below
            dec a               ; first entry is set in frame interrupt
            ld  (p_ld_de+1),a   ; set line count for raster effect
            ld  a,&c0           ; screen height
            sub b               ; subtract image height
            rra                 ; line offset for vertical centre
            and %11111110       ; force even line

            ld  (p_line+1),a    ; set line interrupt point
            exx

            scf                 ; top bit for display address
            rra                 ; y to display MSB
            ld  d,a

            ld  a,&80           ; screen width in bytes
            sub c               ; subtract image width
            ld  e,a             ; display LSB
            srl e               ; centre horizontally

            exx
cpylp:      exx
            push bc
            ldir                ; copy line
            ld  c,a             ; offset to next line start
            ex  de,hl
            add hl,bc           ; advance to next line
            ex  de,hl
            bit 6,h             ; into the upper 16K yet?
            call nz,next_page   ; if so, slide the paging window
            pop bc
            exx
            djnz cpylp          ; loop until all lines copied
            exx

            ld  (p_palette+1),hl ; start of static palette
            ld  de,16           ; 16 entries
            add hl,de
            ld  (p_ld_hl+1),hl  ; start of dynamic palette

            ex  de,hl

            pop hl
            ld  c,h             ; c = height
            dec c               ; static palette includes line 0
            pop hl
            ld  a,l             ; l = dynamic colours
            ld  h,b             ; h = 0
            ld  l,b             ; l = 0
mult_lp:    add hl,bc           ; crude multiply (lines*dcols)
            dec a
            jr  nz,mult_lp

            add hl,de           ; skip entire dynamic palette

            ld  a,(hl)          ; A
            inc hl
            cp  "A"             ; check end signature
            ret nz
            ld  a,(hl)          ; M
            inc hl
            cp  "M"             ; check end signature
            ret

next_page:  ex  af,af'
            in  a,(lmpr)
            inc a               ; next page
            out (lmpr),a
            ex  af,af'
            res 6,h             ; move pointer down 16K
            ret

            defs 64
new_stack:

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Interrupt-driven viewer

            org  &fefe
            dump $

            push af
            push bc
            push de
            push hl
            in  a,(status)      ; check interrupt status
            rra                 ; line interrupt?
            jr  c,not_line      ; jump if not

p_ld_hl:    ld  hl,0            ; start of dynamic palette
p_ld_de:    ld  de,0            ; d = line delay, e = line count
            ld  c,palette       ; palette port

p_ld_b:     ld  b,0             ; delay to left of
            djnz $

line_lp:
            ld  b,&10           ; final CLUT entry +1 for first OUTI
p_jr:       jr  $               ; skip the OUTIs we don't need
            outi                ; the remainder set the dynamic palette
            outi
            outi
            outi
            outi
            outi
            outi
            outi
            outi
            outi
            outi
outi_end:
            ld  b,d
            djnz $              ; wait for next right border
            dec e               ; line_count--
            jr  nz,line_lp      ; loop until all done

            ld  a,&ff
            out (line),a        ; disable line interrupts

int_exit:   pop hl
            pop de
            pop bc
            pop af
            ei
            reti

not_line:   bit 2,a             ; FRAME int (after RRA above)
            jr  nz,int_exit

p_palette:  ld  hl,0
            ld  bc,&10f8
            otir                ; set initial palette

p_line:     ld  a,0             ; set interrupt for starting line
            out (line),a

            jr  int_exit        ; we're done for now

end:

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Sample images, back-to-back

            dump 3,0            ; page 3, offset 0

mdat "images/leopard.sham"
mdat "images/squirrel.sham"
mdat "images/formula1.sham"
mdat "images/newyork.sham"
mdat "images/robocop.sham"
mdat "images/astronaut.sham"
mdat "images/mozart.sham"
mdat "images/mandrill.sham"
mdat "images/lena.sham"
mdat "images/hummingbird.sham"
mdat "images/eye.sham"
mdat "images/banana.sham"
mdat "images/strawberries.sham"
mdat "images/nastassja.sham"
mdat "images/shrek.sham"
mdat "images/sunset.sham"
mdat "images/crayons.sham"
mdat "images/sampalette.sham"

            defb 0              ; end marker
