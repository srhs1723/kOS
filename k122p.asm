; K122P - GUI Kernel
[BITS 16]
[ORG 0x3000]

SCREEN_WIDTH equ 320
SCREEN_HEIGHT equ 200
VIDEO_MEM equ 0xA000

; Colors
COLOR_BLACK equ 0
COLOR_BLUE equ 1
COLOR_GREEN equ 2
COLOR_CYAN equ 3
COLOR_RED equ 4
COLOR_MAGENTA equ 5
COLOR_BROWN equ 6
COLOR_LIGHT_GRAY equ 7
COLOR_DARK_GRAY equ 8
COLOR_LIGHT_BLUE equ 9
COLOR_LIGHT_GREEN equ 10
COLOR_LIGHT_CYAN equ 11
COLOR_LIGHT_RED equ 12
COLOR_LIGHT_MAGENTA equ 13
COLOR_YELLOW equ 14
COLOR_WHITE equ 15

start:
    ; Setup segments
    cli
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x9000
    sti
    
    ; Set VGA mode 320x200x256
    mov ax, 0x0013
    int 0x10
    
    ; Point ES to video memory
    mov ax, VIDEO_MEM
    mov es, ax
    
    ; Draw desktop
    call draw_desktop
    call draw_icons
    
    ; Main loop
main_loop:
    ; Check for keypress
    mov ah, 0x01
    int 0x16
    jz main_loop
    
    ; Get key
    mov ah, 0x00
    int 0x16
    
    ; Check keys
    cmp al, '1'
    je app_files
    cmp al, '2'
    je app_terminal
    cmp al, '3'
    je app_about
    cmp al, 'q'
    je shutdown
    
    jmp main_loop

; ===== APPS =====

app_files:
    call draw_window
    mov bx, 50
    mov dx, 35
    mov si, str_files_title
    mov al, COLOR_WHITE
    call draw_text
    
    mov bx, 50
    mov dx, 50
    mov si, str_file1
    mov al, COLOR_YELLOW
    call draw_text
    
    mov bx, 50
    mov dx, 60
    mov si, str_file2
    mov al, COLOR_YELLOW
    call draw_text
    
    mov bx, 50
    mov dx, 70
    mov si, str_file3
    mov al, COLOR_YELLOW
    call draw_text
    
    call wait_key
    call draw_desktop
    call draw_icons
    jmp main_loop

app_terminal:
    call draw_window
    mov bx, 50
    mov dx, 35
    mov si, str_term_title
    mov al, COLOR_WHITE
    call draw_text
    
    mov bx, 50
    mov dx, 50
    mov si, str_prompt
    mov al, COLOR_GREEN
    call draw_text
    
    mov bx, 50
    mov dx, 60
    mov si, str_output
    mov al, COLOR_LIGHT_GRAY
    call draw_text
    
    call wait_key
    call draw_desktop
    call draw_icons
    jmp main_loop

app_about:
    call draw_window
    mov bx, 70
    mov dx, 50
    mov si, str_about1
    mov al, COLOR_CYAN
    call draw_text
    
    mov bx, 70
    mov dx, 60
    mov si, str_about2
    mov al, COLOR_WHITE
    call draw_text
    
    mov bx, 70
    mov dx, 70
    mov si, str_about3
    mov al, COLOR_WHITE
    call draw_text
    
    call wait_key
    call draw_desktop
    call draw_icons
    jmp main_loop

shutdown:
    ; Black screen
    xor di, di
    xor al, al
    mov cx, 64000
    rep stosb
    
    ; Shutdown message
    mov bx, 100
    mov dx, 90
    mov si, str_shutdown
    mov al, COLOR_WHITE
    call draw_text
    
    cli
    hlt

; ===== DRAWING FUNCTIONS =====

draw_desktop:
    ; Blue background
    xor di, di
    mov al, COLOR_BLUE
    mov cx, 64000
    rep stosb
    
    ; Title bar at top
    xor di, di
    mov al, COLOR_DARK_GRAY
    mov cx, SCREEN_WIDTH * 12
    rep stosb
    
    ; OS name
    mov bx, 10
    mov dx, 2
    mov si, str_os_name
    mov al, COLOR_YELLOW
    call draw_text
    ret

draw_icons:
    ; Icon 1 - Files (Yellow)
    mov bx, 30
    mov dx, 30
    mov al, COLOR_YELLOW
    call draw_icon
    mov bx, 32
    mov dx, 70
    mov si, str_icon1
    mov al, COLOR_WHITE
    call draw_text
    
    ; Icon 2 - Terminal (Green)
    mov bx, 120
    mov dx, 30
    mov al, COLOR_GREEN
    call draw_icon
    mov bx, 118
    mov dx, 70
    mov si, str_icon2
    mov al, COLOR_WHITE
    call draw_text
    
    ; Icon 3 - About (Cyan)
    mov bx, 210
    mov dx, 30
    mov al, COLOR_CYAN
    call draw_icon
    mov bx, 208
    mov dx, 70
    mov si, str_icon3
    mov al, COLOR_WHITE
    call draw_text
    ret

; Draw icon (32x32)
; bx=x, dx=y, al=color
draw_icon:
    push ax
    push cx
    push dx
    push di
    
    mov ah, al  ; Save color
    
    ; Calculate position
    mov ax, dx
    mov cx, SCREEN_WIDTH
    mul cx
    add ax, bx
    mov di, ax
    
    mov al, ah  ; Restore color
    mov dx, 32
.row_loop:
    push di
    mov cx, 32
    rep stosb
    pop di
    add di, SCREEN_WIDTH
    dec dx
    jnz .row_loop
    
    pop di
    pop dx
    pop cx
    pop ax
    ret

draw_window:
    ; Window background (dark gray)
    mov di, 25 * SCREEN_WIDTH + 40
    mov dx, 100
.win_loop:
    push di
    mov al, COLOR_DARK_GRAY
    mov cx, 240
    rep stosb
    pop di
    add di, SCREEN_WIDTH
    dec dx
    jnz .win_loop
    
    ; Title bar (light gray)
    mov di, 25 * SCREEN_WIDTH + 40
    mov al, COLOR_LIGHT_GRAY
    mov cx, 240
    rep stosb
    ret

; Draw text - simple 6x8 char blocks
; bx=x, dx=y, si=string, al=color
draw_text:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    
    mov bp, ax  ; Save color in BP
    
.char_loop:
    lodsb
    test al, al
    jz .done
    
    ; Calculate position
    push ax
    mov ax, dx
    mov cx, SCREEN_WIDTH
    mul cx
    add ax, bx
    mov di, ax
    pop ax
    
    ; Skip spaces
    cmp al, ' '
    je .next_char
    
    ; Draw 6x8 character block
    mov cx, 8
.row:
    push cx
    push di
    mov cx, 5
    mov al, byte [bp]
    rep stosb
    pop di
    add di, SCREEN_WIDTH
    pop cx
    loop .row
    
.next_char:
    add bx, 6
    jmp .char_loop
    
.done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

wait_key:
    mov ah, 0x00
    int 0x16
    ret

; ===== DATA =====

str_os_name: db 'K122P GUI v1.0', 0
str_icon1: db '1-FILES', 0
str_icon2: db '2-TERM', 0
str_icon3: db '3-INFO', 0

str_files_title: db 'FILE BROWSER', 0
str_file1: db 'kernel.bin', 0
str_file2: db 'system.cfg', 0
str_file3: db 'boot.log', 0

str_term_title: db 'TERMINAL', 0
str_prompt: db 'root@k122p:~$', 0
str_output: db 'K122P ready', 0

str_about1: db 'K122P GUI KERNEL', 0
str_about2: db 'Version 1.0', 0
str_about3: db 'JBoot Compatible', 0

str_shutdown: db 'SHUTDOWN', 0

times 9216-($-$$) db 0  ; Pad to 18 sectors (9216 bytes)
