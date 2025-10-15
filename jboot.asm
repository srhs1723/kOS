; JBoot v2.0 - Three Kernel Bootloader
[BITS 16]
[ORG 0x7C00]

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    
    mov ax, 0x0003
    int 0x10
    
    ; Menu
    mov si, banner
    call print
    mov si, opt1
    call print
    mov si, opt2
    call print
    mov si, opt3
    call print
    mov si, info
    call print
    
menu:
    mov ah, 0x00
    int 0x16
    
    cmp al, '1'
    je boot_k122e
    cmp al, '2'
    je boot_k122p
    cmp al, '3'
    je boot_k122a
    
    jmp menu

boot_k122e:
    mov si, load1
    call print
    mov ah, 0x02
    mov al, 9
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov bx, 0x1000
    int 0x13
    jc error
    jmp 0x0000:0x1000

boot_k122p:
    mov si, load2
    call print
    mov ah, 0x02
    mov al, 18
    mov ch, 0
    mov cl, 11
    mov dh, 0
    mov bx, 0x3000
    int 0x13
    jc error
    jmp 0x0000:0x3000

boot_k122a:
    mov si, load3
    call print
    
    ; Save boot drive
    push dx
    
    ; Load K122A in chunks (staying under 63 sector limit)
    ; First chunk: sectors 29-46 (18 sectors)
    pop dx
    push dx
    mov ah, 0x02
    mov al, 18
    mov ch, 0
    mov cl, 29
    mov dh, 0
    mov bx, 0x8000
    int 0x13
    jc error
    
    ; Second chunk: sectors 47-62 (16 sectors, staying under 63)
    pop dx
    push dx
    mov ah, 0x02
    mov al, 16
    mov ch, 0
    mov cl, 47
    mov dh, 0
    mov bx, 0xA400
    int 0x13
    jc error
    
    ; Third chunk: sectors 63+ need different head
    ; Sector 63 on head 0
    pop dx
    push dx
    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, 63
    mov dh, 0
    mov bx, 0xC400
    int 0x13
    jc error
    
    ; Remaining sectors on head 1, starting at sector 1
    pop dx
    mov ah, 0x02
    mov al, 6           ; Last 6 sectors
    mov ch, 0
    mov cl, 1
    mov dh, 1           ; Head 1
    mov bx, 0xC600
    int 0x13
    jc error
    
    pop dx              ; Clean stack
    jmp 0x0000:0x8000

error:
    mov si, err
    call print
    jmp $

print:
    push ax
    mov ah, 0x0E
.loop:
    lodsb
    test al, al
    jz .done
    int 0x10
    jmp .loop
.done:
    pop ax
    ret

banner: db 'JBoot v2.0', 13, 10, 13, 10, 0
opt1: db '1 - K122E Text', 13, 10, 0
opt2: db '2 - K122P GUI', 13, 10, 0
opt3: db '3 - K122A Unix', 13, 10, 13, 10, 0
info: db 'Select: ', 0
load1: db 'K122E...', 13, 10, 0
load2: db 'K122P...', 13, 10, 0
load3: db 'K122A...', 13, 10, 0
err: db 'ERR!', 0

times 510-($-$$) db 0
dw 0xAA55
