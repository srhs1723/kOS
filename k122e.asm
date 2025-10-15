; K122E - Text Terminal Kernel
[BITS 16]
[ORG 0x1000]

start:
    ; Setup segments
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x9000
    sti
    
    ; Clear screen
    mov ax, 0x0003
    int 0x10
    
    ; Show kernel info
    mov si, banner
    call print_string
    
    ; Main shell loop
shell_loop:
    mov si, prompt
    call print_string
    
    ; Read command
    mov di, cmd_buffer
    call read_line
    
    ; Check commands
    mov si, cmd_buffer
    cmp byte [si], 0
    je shell_loop
    
    ; Check "help"
    mov di, cmd_help
    call str_cmp
    je show_help
    
    ; Check "clear"
    mov di, cmd_clear
    call str_cmp
    je do_clear
    
    ; Check "info"
    mov di, cmd_info
    call str_cmp
    je show_info
    
    ; Check "reboot"
    mov di, cmd_reboot
    call str_cmp
    je do_reboot
    
    ; Check "halt"
    mov di, cmd_halt
    call str_cmp
    je do_halt
    
    ; Unknown command
    mov si, msg_unknown
    call print_string
    jmp shell_loop

show_help:
    mov si, help_text
    call print_string
    jmp shell_loop

do_clear:
    mov ax, 0x0003
    int 0x10
    mov si, banner
    call print_string
    jmp shell_loop

show_info:
    mov si, info_text
    call print_string
    jmp shell_loop

do_reboot:
    mov si, msg_reboot
    call print_string
    mov cx, 0xFFFF
.wait:
    loop .wait
    int 0x19

do_halt:
    mov si, msg_halt
    call print_string
    cli
    hlt

; ===== FUNCTIONS =====

print_string:
    push ax
    push bx
    mov ah, 0x0E
.loop:
    lodsb
    test al, al
    jz .done
    int 0x10
    jmp .loop
.done:
    pop bx
    pop ax
    ret

read_line:
    push ax
    push cx
    xor cx, cx
.loop:
    mov ah, 0x00
    int 0x16
    
    cmp al, 0x0D
    je .done
    
    cmp al, 0x08
    je .backspace
    
    cmp al, 0x20
    jl .loop
    
    cmp cx, 60
    jge .loop
    
    mov ah, 0x0E
    int 0x10
    stosb
    inc cx
    jmp .loop
    
.backspace:
    test cx, cx
    jz .loop
    dec di
    dec cx
    mov ah, 0x0E
    mov al, 0x08
    int 0x10
    mov al, 0x20
    int 0x10
    mov al, 0x08
    int 0x10
    jmp .loop
    
.done:
    xor al, al
    stosb
    mov ah, 0x0E
    mov al, 0x0D
    int 0x10
    mov al, 0x0A
    int 0x10
    pop cx
    pop ax
    ret

str_cmp:
    push si
    push di
.loop:
    lodsb
    mov bl, [di]
    inc di
    cmp al, bl
    jne .not_equal
    test al, al
    jz .equal
    jmp .loop
.equal:
    pop di
    pop si
    xor ax, ax
    ret
.not_equal:
    pop di
    pop si
    mov ax, 1
    ret

; ===== DATA =====

banner:
    db '================================================', 13, 10
    db '  K122E - Text Terminal Kernel v1.0', 13, 10
    db '================================================', 13, 10
    db 'Type "help" for available commands', 13, 10, 13, 10, 0

prompt: db 'k122e> ', 0

cmd_help: db 'help', 0
cmd_clear: db 'clear', 0
cmd_info: db 'info', 0
cmd_reboot: db 'reboot', 0
cmd_halt: db 'halt', 0

help_text:
    db 'Available commands:', 13, 10
    db '  help    - Show this help', 13, 10
    db '  clear   - Clear screen', 13, 10
    db '  info    - System information', 13, 10
    db '  reboot  - Reboot system', 13, 10
    db '  halt    - Halt system', 13, 10, 13, 10, 0

info_text:
    db 'System Information:', 13, 10
    db '  Kernel: K122E v1.0', 13, 10
    db '  Mode: 16-bit Real Mode', 13, 10
    db '  Type: Text Terminal', 13, 10
    db '  Bootloader: JBoot v1.0', 13, 10, 13, 10, 0

msg_unknown: db 'Unknown command. Type "help"', 13, 10, 0
msg_reboot: db 'Rebooting...', 13, 10, 0
msg_halt: db 'System halted.', 13, 10, 0

cmd_buffer: times 64 db 0

times 4608-($-$$) db 0  ; Pad to 9 sectors (4608 bytes)
