; K122A - Advanced Unix-like Kernel
; Real filesystem, real processes, 60 commands
[BITS 16]
[ORG 0x8000]

; === CONSTANTS ===
MAX_FILES equ 64
MAX_DIRS equ 16
MAX_PROCS equ 11
FILE_NAME_LEN equ 32
FILE_DATA_LEN equ 128

; File types
TYPE_FILE equ 0
TYPE_DIR equ 1

; UIDs
UID_ROOT equ 0
UID_KERNEL equ 1
UID_APP equ 100
UID_USER equ 1000

start:
    cli
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x9000
    sti
    
    ; Clear screen and show we're alive
    mov ax, 0x0003
    int 0x10
    
    ; Print immediate debug
    mov si, debug_start
    call print
    
    ; Initialize systems
    call vfs_init
    call proc_init
    call show_boot
    
    ; Simple shell for now
shell_loop:
    mov si, prompt
    call print
    
    mov di, cmd_buf
    call read_line
    
    ; Parse command
    call exec_cmd
    jmp shell_loop

; ========================================
; VFS - Virtual Filesystem (RAM-based)
; ========================================

vfs_init:
    ; Clear file table
    mov di, file_table
    mov cx, MAX_FILES * 192  ; 192 bytes per file entry
    xor al, al
    rep stosb
    
    ; Create root directory structure
    call vfs_create_root_dirs
    
    ; Create initial system files
    call vfs_create_system_files
    
    mov word [vfs_file_count], 5
    mov byte [vfs_current_dir], 0  ; Start at root
    
    ret

; Create the Unix directory structure
vfs_create_root_dirs:
    ; /system
    mov si, str_system
    mov al, TYPE_DIR
    mov bl, UID_ROOT
    call vfs_create_entry
    
    ; /etc
    mov si, str_etc
    mov al, TYPE_DIR
    mov bl, UID_ROOT
    call vfs_create_entry
    
    ; /home
    mov si, str_home
    mov al, TYPE_DIR
    mov bl, UID_USER
    call vfs_create_entry
    
    ; /dev
    mov si, str_dev
    mov al, TYPE_DIR
    mov bl, UID_ROOT
    call vfs_create_entry
    
    ; /sys
    mov si, str_sys
    mov al, TYPE_DIR
    mov bl, UID_KERNEL
    call vfs_create_entry
    
    ret

; Create system files with actual content
vfs_create_system_files:
    ; /system/kernel.bin
    mov si, str_system_kernel
    mov di, data_kernel
    mov al, TYPE_FILE
    mov bl, UID_KERNEL
    mov cx, 25  ; data length
    call vfs_create_file_with_data
    
    ret

; Create VFS entry (file or directory)
; SI = name, AL = type, BL = uid
vfs_create_entry:
    push ax
    push bx
    push cx
    push di
    push si
    
    ; Get next free slot
    mov ax, [vfs_file_count]
    mov cx, 192
    mul cx
    mov di, file_table
    add di, ax
    
    ; Copy name (32 bytes)
    mov cx, FILE_NAME_LEN
.copy_name:
    lodsb
    stosb
    test al, al
    jz .name_done
    loop .copy_name
.name_done:
    ; Pad rest of name
    mov al, 0
    rep stosb
    
    pop si
    push si
    
    ; Set type (offset 32)
    pop ax
    push ax
    mov byte [di+32], al
    
    ; Set UID (offset 33)
    mov byte [di+33], bl
    
    ; Set permissions (offset 34)
    cmp al, TYPE_DIR
    je .dir_perms
    mov byte [di+34], 0x64  ; 644
    jmp .perms_done
.dir_perms:
    mov byte [di+34], 0x75  ; 755
.perms_done:
    
    ; Size (offset 35-36)
    mov word [di+35], 0
    
    pop si
    pop di
    pop cx
    pop bx
    pop ax
    ret

; Create file with data
; SI = name, DI = data, AL = type, BL = uid, CX = data length
vfs_create_file_with_data:
    call vfs_create_entry
    
    ; Copy data to file entry
    push si
    push di
    push cx
    
    mov ax, [vfs_file_count]
    push ax
    mov bx, 192
    mul bx
    mov si, file_table
    add si, ax
    add si, 64  ; Data offset
    
    pop ax
    inc word [vfs_file_count]
    
    pop cx
    pop di
    
    ; DI = source, SI = dest, CX = length
.copy:
    push cx
    mov al, [di]
    mov [si], al
    inc si
    inc di
    pop cx
    loop .copy
    
    pop si
    ret

; ========================================
; PROCESS MANAGEMENT
; ========================================

proc_init:
    ; Clear process table
    mov di, proc_table
    mov cx, MAX_PROCS * 64  ; 64 bytes per process
    xor al, al
    rep stosb
    
    ; Create kernel processes (PID 1-7, UID 1)
    mov di, proc_table
    mov byte [di], 1        ; PID
    mov byte [di+1], UID_KERNEL  ; UID
    mov byte [di+2], 1      ; State: running
    mov byte [di+3], 5      ; CPU: 5%
    mov word [di+4], proc_name_init
    mov word [di+6], 0      ; Parent: 0
    mov word [di+8], 4      ; Memory: 4KB
    
    mov di, proc_table + 64
    mov byte [di], 2
    mov byte [di+1], UID_KERNEL
    mov byte [di+2], 1
    mov byte [di+3], 10     ; CPU: 10%
    mov word [di+4], proc_name_sched
    mov word [di+6], 1      ; Parent: init
    mov word [di+8], 2      ; Memory: 2KB
    
    mov di, proc_table + 128
    mov byte [di], 3
    mov byte [di+1], UID_KERNEL
    mov byte [di+2], 1
    mov byte [di+3], 8      ; CPU: 8%
    mov word [di+4], proc_name_vfs
    mov word [di+6], 1
    mov word [di+8], 8      ; Memory: 8KB
    
    mov di, proc_table + 192
    mov byte [di], 4
    mov byte [di+1], UID_KERNEL
    mov byte [di+2], 1
    mov word [di+4], proc_name_mem
    
    mov di, proc_table + 256
    mov byte [di], 5
    mov byte [di+1], UID_KERNEL
    mov byte [di+2], 1
    mov word [di+4], proc_name_net
    
    mov di, proc_table + 320
    mov byte [di], 6
    mov byte [di+1], UID_KERNEL
    mov byte [di+2], 1
    mov word [di+4], proc_name_tty
    
    mov di, proc_table + 384
    mov byte [di], 7
    mov byte [di+1], UID_KERNEL
    mov byte [di+2], 1
    mov word [di+4], proc_name_disk
    
    ; App processes (PID 8-10, UID 100)
    mov di, proc_table + 448
    mov byte [di], 8
    mov byte [di+1], UID_APP
    mov byte [di+2], 1
    mov word [di+4], proc_name_app1
    
    mov di, proc_table + 512
    mov byte [di], 9
    mov byte [di+1], UID_APP
    mov byte [di+2], 1
    mov word [di+4], proc_name_app2
    
    mov di, proc_table + 576
    mov byte [di], 10
    mov byte [di+1], UID_APP
    mov byte [di+2], 1
    mov word [di+4], proc_name_app3
    
    ; User process (PID 11, UID 1000)
    mov di, proc_table + 640
    mov byte [di], 11
    mov byte [di+1], UID_USER
    mov byte [di+2], 1
    mov word [di+4], proc_name_shell
    
    mov word [proc_count], 11
    
    ; Initialize process stats
    mov word [file_ops], 0
    mov word [sched_ticks], 0
    ret

; Update process stats (called on commands)
update_proc_stats:
    inc word [file_ops]
    inc word [sched_ticks]
    inc word [tty_chars]
    ret

; ========================================
; COMMAND EXECUTION
; ========================================

exec_cmd:
    mov si, cmd_buf
    cmp byte [si], 0
    je .done
    
    ; Update process statistics
    call update_proc_stats
    
    ; Parse command and arguments
    call parse_cmd_args
    
    ; Check ls
    mov di, cmd_ls
    call strcmp
    je cmd_ls_exec
    
    ; Check pwd
    mov di, cmd_pwd
    call strcmp
    je cmd_pwd_exec
    
    ; Check cat
    mov di, cmd_cat
    call strcmp
    je cmd_cat_exec
    
    ; Check help
    mov di, cmd_help
    call strcmp
    je cmd_help_exec
    
    ; Check ps
    mov di, cmd_ps
    call strcmp
    je cmd_ps_exec
    
    ; Check mkdir
    mov di, cmd_mkdir
    call strcmp
    je cmd_mkdir_exec
    
    ; Check touch
    mov di, cmd_touch
    call strcmp
    je cmd_touch_exec
    
    ; Check rm
    mov di, cmd_rm
    call strcmp
    je cmd_rm_exec
    
    ; Check echo
    mov di, cmd_echo
    call strcmp
    je cmd_echo_exec
    
    ; Check clear
    mov di, cmd_clear
    call strcmp
    je cmd_clear_exec
    
    ; Check cd
    mov di, cmd_cd
    call strcmp
    je cmd_cd_exec
    
    ; Check uname
    mov di, cmd_uname
    call strcmp
    je cmd_uname_exec
    
    ; Check whoami
    mov di, cmd_whoami
    call strcmp
    je cmd_whoami_exec
    
    ; Check chmod
    mov di, cmd_chmod
    call strcmp
    je cmd_chmod_exec
    
    ; Check kill
    mov di, cmd_kill
    call strcmp
    je cmd_kill_exec
    
    ; Check cp
    mov di, cmd_cp
    call strcmp
    je cmd_cp_exec
    
    ; Check mv
    mov di, cmd_mv
    call strcmp
    je cmd_mv_exec
    
    ; Check df
    mov di, cmd_df
    call strcmp
    je cmd_df_exec
    
    ; Check free
    mov di, cmd_free
    call strcmp
    je cmd_free_exec
    
    ; Check uptime
    mov di, cmd_uptime
    call strcmp
    je cmd_uptime_exec
    
    ; Check date
    mov di, cmd_date
    call strcmp
    je cmd_date_exec
    
    ; Check hostname
    mov di, cmd_hostname
    call strcmp
    je cmd_hostname_exec
    
    ; Check reboot
    mov di, cmd_reboot
    call strcmp
    je cmd_reboot_exec
    
    ; Check halt
    mov di, cmd_halt
    call strcmp
    je cmd_halt_exec
    
    ; Check grep
    mov di, cmd_grep
    call strcmp
    je cmd_grep_exec
    
    ; Check find
    mov di, cmd_find
    call strcmp
    je cmd_find_exec
    
    ; Check wc
    mov di, cmd_wc
    call strcmp
    je cmd_wc_exec
    
    ; Check head
    mov di, cmd_head
    call strcmp
    je cmd_head_exec
    
    ; Check tail
    mov di, cmd_tail
    call strcmp
    je cmd_tail_exec
    
    ; Check env
    mov di, cmd_env
    call strcmp
    je cmd_env_exec
    
    ; Batch 3 - Final 30
    mov di, cmd_top
    call strcmp
    je cmd_top_exec
    mov di, cmd_vmstat
    call strcmp
    je cmd_vmstat_exec
    mov di, cmd_dmesg
    call strcmp
    je cmd_dmesg_exec
    mov di, cmd_lsof
    call strcmp
    je cmd_lsof_exec
    mov di, cmd_netstat
    call strcmp
    je cmd_netstat_exec
    mov di, cmd_ifconfig
    call strcmp
    je cmd_ifconfig_exec
    mov di, cmd_ping
    call strcmp
    je cmd_ping_exec
    mov di, cmd_wget
    call strcmp
    je cmd_wget_exec
    mov di, cmd_curl
    call strcmp
    je cmd_curl_exec
    mov di, cmd_tar
    call strcmp
    je cmd_tar_exec
    mov di, cmd_gzip
    call strcmp
    je cmd_gzip_exec
    mov di, cmd_zip
    call strcmp
    je cmd_zip_exec
    mov di, cmd_mount
    call strcmp
    je cmd_mount_exec
    mov di, cmd_umount
    call strcmp
    je cmd_umount_exec
    mov di, cmd_fdisk
    call strcmp
    je cmd_fdisk_exec
    mov di, cmd_mkfs
    call strcmp
    je cmd_mkfs_exec
    mov di, cmd_fsck
    call strcmp
    je cmd_fsck_exec
    mov di, cmd_su
    call strcmp
    je cmd_su_exec
    mov di, cmd_sudo
    call strcmp
    je cmd_sudo_exec
    mov di, cmd_passwd
    call strcmp
    je cmd_passwd_exec
    mov di, cmd_chgrp
    call strcmp
    je cmd_chgrp_exec
    mov di, cmd_ln
    call strcmp
    je cmd_ln_exec
    mov di, cmd_stat
    call strcmp
    je cmd_stat_exec
    mov di, cmd_du
    call strcmp
    je cmd_du_exec
    mov di, cmd_man
    call strcmp
    je cmd_man_exec
    mov di, cmd_which
    call strcmp
    je cmd_which_exec
    mov di, cmd_alias
    call strcmp
    je cmd_alias_exec
    mov di, cmd_history
    call strcmp
    je cmd_history_exec
    mov di, cmd_export
    call strcmp
    je cmd_export_exec
    mov di, cmd_source
    call strcmp
    je cmd_source_exec
    
    ; Unknown
    mov si, msg_unknown
    call print
    
.done:
    ret

; === COMMAND: ls ===
cmd_ls_exec:
    mov si, msg_ls_header
    call print
    
    ; Iterate through file table
    mov cx, [vfs_file_count]
    mov di, file_table
    
.loop:
    push cx
    push di
    
    ; Print permissions
    mov al, [di+34]
    call print_octal
    mov si, msg_space
    call print
    
    ; Print UID
    mov al, [di+33]
    call print_num
    mov si, msg_space
    call print
    
    ; Print size
    mov ax, [di+35]
    mov al, ah
    call print_num
    mov si, msg_space
    call print
    
    ; Print name
    mov si, di
    call print
    
    ; Check if directory
    mov al, [di+32]
    cmp al, TYPE_DIR
    jne .is_file
    mov si, msg_dir_indicator
    call print
    jmp .next
    
.is_file:
    mov si, msg_newline
    call print
    
.next:
    pop di
    add di, 192
    pop cx
    loop .loop
    
    ret

; === COMMAND: pwd ===
cmd_pwd_exec:
    ; Show current directory path
    mov al, [vfs_current_dir]
    test al, al
    jz .root
    
    ; Get directory name
    xor ah, ah
    mov bx, 192
    mul bx
    mov si, file_table
    add si, ax
    
    mov al, '/'
    mov ah, 0x0E
    int 0x10
    
    call print
    mov si, msg_newline
    call print
    ret
    
.root:
    mov si, msg_root
    call print
    ret

; === COMMAND: cat ===
cmd_cat_exec:
    ; Search for file by name if argument provided
    cmp byte [cmd_args], 0
    je .default_file
    
    ; Search filesystem for file
    mov cx, [vfs_file_count]
    mov di, file_table
.search_loop:
    push cx
    push di
    
    ; Compare name
    mov si, cmd_args
    push di
.name_cmp:
    lodsb
    mov bl, [di]
    inc di
    cmp al, bl
    jne .no_match
    test al, al
    jnz .name_cmp
    ; Found!
    pop di
    add di, 64  ; Data offset
    mov si, di
    call print
    mov si, msg_newline
    call print
    pop di
    pop cx
    ret
    
.no_match:
    pop di
    pop di
    add di, 192
    pop cx
    loop .search_loop
    
    ; Not found
    mov si, msg_cat_notfound
    call print
    ret
    
.default_file:
    ; Cat the kernel file
    mov si, file_table
    add si, 192  ; Skip to file (after dirs)
    add si, 64   ; Jump to data section
    call print
    mov si, msg_newline
    call print
    ret

; === COMMAND: help ===
cmd_help_exec:
    mov si, help_text
    call print
    ret

; === COMMAND: ps ===
cmd_ps_exec:
    mov si, ps_header
    call print
    
    ; Iterate through process table
    mov cx, [proc_count]
    mov di, proc_table
    
.loop:
    push cx
    push di
    
    ; Print PID
    mov al, [di]
    call print_num
    mov si, ps_space
    call print
    
    ; Print Parent PID
    mov ax, [di+6]
    mov al, ah
    call print_num
    mov si, ps_space
    call print
    
    ; Print CPU%
    mov al, [di+3]
    call print_num
    mov si, ps_percent
    call print
    
    ; Print Memory
    mov ax, [di+8]
    mov al, ah
    call print_num
    mov si, ps_kb
    call print
    
    ; Print state
    mov al, [di+2]
    cmp al, 1
    je .running
    mov si, ps_state_sleep
    jmp .print_state
.running:
    mov si, ps_state_run
.print_state:
    call print
    mov si, ps_space
    call print
    
    ; Print name
    mov si, [di+4]
    call print
    mov si, msg_newline
    call print
    
    pop di
    add di, 64
    pop cx
    loop .loop
    
    ret

; === COMMAND: mkdir ===
cmd_mkdir_exec:
    ; Check if argument provided
    cmp byte [cmd_args], 0
    je .use_default
    ; Use argument as name
    mov si, cmd_args
    jmp .create
.use_default:
    mov si, str_newdir
.create:
    mov al, TYPE_DIR
    mov bl, UID_USER
    call vfs_create_entry
    inc word [vfs_file_count]
    mov si, msg_mkdir_ok
    call print
    ret

; === COMMAND: touch ===
cmd_touch_exec:
    ; Check if argument provided
    cmp byte [cmd_args], 0
    je .use_default
    ; Use argument as name
    mov si, cmd_args
    jmp .create
.use_default:
    mov si, str_newfile
.create:
    mov al, TYPE_FILE
    mov bl, UID_USER
    call vfs_create_entry
    inc word [vfs_file_count]
    mov si, msg_touch_ok
    call print
    ret

; === COMMAND: rm ===
cmd_rm_exec:
    ; Delete file by name (if arg provided)
    cmp byte [cmd_args], 0
    je .no_arg
    
    ; Search for file
    mov cx, [vfs_file_count]
    mov di, file_table
    xor bx, bx  ; Index counter
    
.search:
    push cx
    push di
    push bx
    
    ; Compare names
    mov si, cmd_args
    push di
.cmp_name:
    lodsb
    mov bl, [di]
    inc di
    cmp al, bl
    jne .no_match
    test al, al
    jnz .cmp_name
    
    ; Found! Delete by shifting entries
    pop di
    pop bx
    
    ; Shift all entries after this one
    mov ax, bx
    mov cx, 192
    mul cx
    mov si, file_table
    add si, ax
    mov di, si
    add si, 192
    
    ; Calculate remaining entries
    mov ax, [vfs_file_count]
    sub ax, bx
    dec ax
    mov cx, 192
    mul cx
    mov cx, ax
    rep movsb
    
    dec word [vfs_file_count]
    pop cx
    mov si, msg_rm_ok
    call print
    ret
    
.no_match:
    pop di
    pop bx
    inc bx
    add di, 192
    pop cx
    loop .search
    
    mov si, msg_rm_err
    call print
    ret
    
.no_arg:
    ; Just decrement if no arg
    cmp word [vfs_file_count], 1
    jle .error
    dec word [vfs_file_count]
    mov si, msg_rm_ok
    call print
    ret
.error:
    mov si, msg_rm_err
    call print
    ret

; === COMMAND: echo ===
cmd_echo_exec:
    ; Echo arguments or default message
    cmp byte [cmd_args], 0
    je .default
    ; Print arguments
    mov si, cmd_args
    call print
    mov si, msg_newline
    call print
    ret
.default:
    mov si, msg_echo_out
    call print
    ret

; === COMMAND: clear ===
cmd_clear_exec:
    mov ax, 0x0003
    int 0x10
    mov si, banner
    call print
    ret

; === COMMAND: cd ===
cmd_cd_exec:
    ; Change to directory by name
    cmp byte [cmd_args], 0
    je .show_current
    
    ; Search for directory
    mov cx, [vfs_file_count]
    mov di, file_table
    xor bx, bx
    
.search:
    push cx
    push di
    push bx
    
    ; Check if directory
    cmp byte [di+32], TYPE_DIR
    jne .not_dir
    
    ; Compare name
    mov si, cmd_args
    push di
.cmp:
    lodsb
    mov bl, [di]
    inc di
    cmp al, bl
    jne .no_match
    test al, al
    jnz .cmp
    
    ; Found! Set as current
    pop di
    pop bx
    mov [vfs_current_dir], bl
    pop cx
    mov si, msg_cd_ok
    call print
    ret
    
.no_match:
    pop di
.not_dir:
    pop bx
    inc bx
    add di, 192
    pop cx
    loop .search
    
    mov si, msg_cd_err
    call print
    ret
    
.show_current:
    mov si, msg_cd_current
    call print
    mov al, [vfs_current_dir]
    call print_num
    mov si, msg_newline
    call print
    ret

; === COMMAND: uname ===
cmd_uname_exec:
    mov si, msg_uname
    call print
    ret

; === COMMAND: whoami ===
cmd_whoami_exec:
    mov si, msg_whoami
    call print
    ret

; === COMMAND: chmod ===
cmd_chmod_exec:
    ; Change permissions of last file
    cmp word [vfs_file_count], 0
    je .error
    
    ; Get last file
    mov ax, [vfs_file_count]
    dec ax
    mov bx, 192
    mul bx
    mov di, file_table
    add di, ax
    add di, 34  ; Permissions offset
    
    ; Toggle permissions
    mov al, [di]
    xor al, 0x11
    mov [di], al
    
    mov si, msg_chmod_ok
    call print
    ret
    
.error:
    mov si, msg_chmod_err
    call print
    ret

; === COMMAND: kill ===
cmd_kill_exec:
    ; Kill process by PID (last process if no arg)
    cmp word [proc_count], 1
    jle .error
    
    ; Get last process
    mov ax, [proc_count]
    dec ax
    mov bx, 64
    mul bx
    mov di, proc_table
    add di, ax
    
    ; Check if already dead
    cmp byte [di+2], 0
    je .already_dead
    
    ; Kill it (set state to 0)
    mov byte [di+2], 0
    
    mov si, msg_kill_ok
    call print
    ret
    
.already_dead:
    mov si, msg_kill_already
    call print
    ret
    
.error:
    mov si, msg_kill_err
    call print
    ret

; === COMMAND: cp ===
cmd_cp_exec:
    ; Copy last file (simplified)
    cmp word [vfs_file_count], MAX_FILES - 1
    jge .full
    
    ; Get last file
    mov ax, [vfs_file_count]
    dec ax
    mov bx, 192
    mul bx
    mov si, file_table
    add si, ax
    
    ; Copy to new slot
    mov ax, [vfs_file_count]
    mov bx, 192
    mul bx
    mov di, file_table
    add di, ax
    
    ; Copy 192 bytes
    mov cx, 192
    rep movsb
    
    inc word [vfs_file_count]
    mov si, msg_cp_ok
    call print
    ret
    
.full:
    mov si, msg_fs_full
    call print
    ret

; === COMMAND: mv ===
cmd_mv_exec:
    ; Rename file (change name of last file)
    cmp word [vfs_file_count], 0
    je .error
    
    ; Get last file
    mov ax, [vfs_file_count]
    dec ax
    mov bx, 192
    mul bx
    mov di, file_table
    add di, ax
    
    ; Change name to "moved"
    mov si, str_moved
    mov cx, 16
.copy:
    lodsb
    stosb
    loop .copy
    
    mov si, msg_mv_ok
    call print
    ret
    
.error:
    mov si, msg_mv_err
    call print
    ret

; === COMMAND: df ===
cmd_df_exec:
    mov si, msg_df
    call print
    ret

; === COMMAND: free ===
cmd_free_exec:
    mov si, msg_free
    call print
    ret

; === COMMAND: uptime ===
cmd_uptime_exec:
    mov si, msg_uptime
    call print
    ret

; === COMMAND: date ===
cmd_date_exec:
    mov si, msg_date
    call print
    ret

; === COMMAND: hostname ===
cmd_hostname_exec:
    mov si, msg_hostname
    call print
    ret

; === COMMAND: reboot ===
cmd_reboot_exec:
    mov si, msg_rebooting
    call print
    int 0x19

; === COMMAND: halt ===
cmd_halt_exec:
    mov si, msg_halting
    call print
    cli
    hlt

; === COMMAND: grep ===
cmd_grep_exec:
    ; Search file content for text
    cmp byte [cmd_args], 0
    je .no_args
    
    ; Search all files
    mov cx, [vfs_file_count]
    mov di, file_table
    
.search_files:
    push cx
    push di
    
    ; Skip directories
    cmp byte [di+32], TYPE_DIR
    je .next
    
    ; Search file data
    push di
    add di, 64  ; Data offset
    mov si, cmd_args
    
.search_data:
    mov al, [si]
    test al, al
    jz .found  ; Full match
    cmp byte [di], 0
    je .next  ; End of data
    cmp al, [di]
    je .char_match
    inc di
    jmp .search_data
    
.char_match:
    inc si
    inc di
    jmp .search_data
    
.found:
    pop di
    mov si, di
    call print
    mov si, msg_colon
    call print
    add di, 64
    mov si, di
    call print
    mov si, msg_newline
    call print
    pop di
    pop cx
    ret
    
.next:
    pop di
    pop di
    add di, 192
    pop cx
    loop .search_files
    ret
    
.no_args:
    mov si, msg_grep_noargs
    call print
    ret

; === COMMAND: find ===
cmd_find_exec:
    ; Find files by partial name match
    cmp byte [cmd_args], 0
    je .show_all
    
    ; Search for matching files
    mov cx, [vfs_file_count]
    mov di, file_table
    xor bx, bx
    
.search:
    push cx
    push di
    push bx
    
    ; Check if name contains search term
    mov si, cmd_args
    push di
.check:
    mov al, [si]
    test al, al
    jz .found  ; End of search term = match
    cmp byte [di], 0
    je .no_match  ; End of filename
    cmp al, [di]
    je .char_match
    inc di
    jmp .check
.char_match:
    inc si
    inc di
    jmp .check
    
.found:
    pop di
    mov si, di
    call print
    mov si, msg_newline
    call print
    pop bx
    inc bx
    add di, 192
    pop cx
    loop .search
    ret
    
.no_match:
    pop di
    pop bx
    inc bx
    add di, 192
    pop cx
    loop .search
    ret
    
.show_all:
    ; No args, show all files
    mov cx, [vfs_file_count]
    mov di, file_table
.list:
    push cx
    push di
    mov si, di
    call print
    mov si, msg_newline
    call print
    pop di
    add di, 192
    pop cx
    loop .list
    ret

; === COMMAND: wc ===
cmd_wc_exec:
    ; Count lines, words, bytes in all files
    xor dx, dx  ; Total bytes
    mov cx, [vfs_file_count]
    mov di, file_table
    
.count_loop:
    push cx
    push di
    
    ; Skip directories
    cmp byte [di+32], TYPE_DIR
    je .skip
    
    ; Count data bytes
    add di, 64
    push dx
.count_bytes:
    cmp byte [di], 0
    je .done_counting
    inc dx
    inc di
    jmp .count_bytes
    
.done_counting:
    pop dx
    
.skip:
    pop di
    add di, 192
    pop cx
    loop .count_loop
    
    ; Print result
    mov si, msg_wc_bytes
    call print
    mov al, dl
    call print_num
    mov si, msg_newline
    call print
    ret

; === COMMAND: head ===
cmd_head_exec:
    ; Show first 10 bytes of last file
    cmp word [vfs_file_count], 0
    je .no_files
    
    mov ax, [vfs_file_count]
    dec ax
    mov bx, 192
    mul bx
    mov si, file_table
    add si, ax
    add si, 64  ; Data offset
    
    ; Print first 10 chars
    mov cx, 10
.print_loop:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    loop .print_loop
    
.done:
    mov si, msg_newline
    call print
    ret
    
.no_files:
    mov si, msg_head_err
    call print
    ret

; === COMMAND: tail ===
cmd_tail_exec:
    ; Show last 10 bytes of last file
    cmp word [vfs_file_count], 0
    je .no_files
    
    mov ax, [vfs_file_count]
    dec ax
    mov bx, 192
    mul bx
    mov si, file_table
    add si, ax
    add si, 64  ; Data offset
    
    ; Find end of data
    mov cx, 128
.find_end:
    lodsb
    test al, al
    jz .found_end
    loop .find_end
    
.found_end:
    ; Back up 10 chars
    sub si, 10
    cmp si, file_table
    jl .at_start
    
    ; Print last 10
    mov cx, 10
.print_loop:
    lodsb
    mov ah, 0x0E
    int 0x10
    loop .print_loop
    
.at_start:
    mov si, msg_newline
    call print
    ret
    
.no_files:
    mov si, msg_tail_err
    call print
    ret

; === COMMAND: env ===
cmd_env_exec:
    mov si, msg_env
    call print
    ret

; Final 30 commands
cmd_top_exec:
    ; Show live process stats
    mov si, msg_top_header
    call print
    
    ; Show system stats
    mov si, msg_top_vfs
    call print
    mov ax, [file_ops]
    mov al, al
    call print_num
    mov si, msg_newline
    call print
    
    mov si, msg_top_sched
    call print
    mov ax, [sched_ticks]
    mov al, al
    call print_num
    mov si, msg_newline
    call print
    
    mov si, msg_top_tty
    call print
    mov ax, [tty_chars]
    mov al, al
    call print_num
    mov si, msg_newline
    call print
    
    ; Count running processes
    xor bx, bx  ; Running count
    mov cx, [proc_count]
    mov di, proc_table
    
.count:
    push cx
    cmp byte [di+2], 1  ; Check if running
    jne .skip
    inc bx
.skip:
    add di, 64
    pop cx
    loop .count
    
    mov si, msg_top_running
    call print
    mov al, bl
    call print_num
    mov si, msg_top_total
    call print
    mov ax, [proc_count]
    mov al, al
    call print_num
    mov si, msg_newline
    call print
    ret
cmd_vmstat_exec:
    ; Show memory statistics
    mov si, msg_vmstat_header
    call print
    
    ; Calculate memory usage
    mov ax, [vfs_file_count]
    mov bx, 192
    mul bx
    shr ax, 10
    
    mov si, msg_vmstat_used
    call print
    mov al, al
    call print_num
    mov si, msg_vmstat_kb
    call print
    ret
cmd_dmesg_exec:
    ; Show kernel messages
    mov si, msg_dmesg_boot
    call print
    mov si, msg_dmesg_vfs
    call print
    mov si, msg_dmesg_proc
    call print
    ret
cmd_lsof_exec:
    ; List open files (show processes with file access)
    mov si, msg_lsof_header
    call print
    
    ; Show first 3 processes
    mov cx, 3
    mov di, proc_table
    
.show_loop:
    push cx
    push di
    
    ; Print PID
    mov al, [di]
    call print_num
    mov si, msg_space
    call print
    
    ; Print name
    mov si, [di+4]
    call print
    mov si, msg_lsof_file
    call print
    
    pop di
    add di, 64
    pop cx
    loop .show_loop
    
    ret
cmd_netstat_exec:
    ; Show network statistics
    mov si, msg_netstat_header
    call print
    
    cmp byte [net_enabled], 1
    je .show_active
    
    mov si, msg_netstat_none
    call print
    ret
    
.show_active:
    mov si, msg_netstat_active
    call print
    ret
cmd_ifconfig_exec:
    ; Show network interfaces
    mov si, msg_ifconfig_header
    call print
    
    ; lo0 (loopback)
    mov si, msg_ifconfig_lo
    call print
    
    ; Check if "network" is enabled
    cmp byte [net_enabled], 1
    je .net_up
    mov si, msg_ifconfig_down
    call print
    ret
    
.net_up:
    mov si, msg_ifconfig_up
    call print
    ret
cmd_ping_exec:
    ; Ping localhost
    cmp byte [net_enabled], 0
    je .net_down
    
    mov si, msg_ping_reply
    call print
    ret
    
.net_down:
    mov si, msg_ping_fail
    call print
    ret
cmd_wget_exec:
    ; Download simulation - create new file
    cmp word [vfs_file_count], MAX_FILES - 1
    jge .full
    
    mov si, str_downloaded
    mov al, TYPE_FILE
    mov bl, UID_USER
    call vfs_create_entry
    inc word [vfs_file_count]
    
    mov si, msg_wget_ok
    call print
    ret
    
.full:
    mov si, msg_fs_full
    call print
    ret
cmd_curl_exec:
    ; HTTP request simulation
    cmp byte [net_enabled], 0
    je .no_net
    
    mov si, msg_curl_response
    call print
    ret
    
.no_net:
    mov si, msg_curl_err
    call print
    ret
cmd_tar_exec:
    ; Create archive (mark files as archived)
    mov si, msg_tar_creating
    call print
    mov ax, [vfs_file_count]
    mov al, al
    call print_num
    mov si, msg_tar_files
    call print
    ret
cmd_gzip_exec:
    ; Toggle compression flag
    xor byte [compression_enabled], 1
    cmp byte [compression_enabled], 1
    je .enabled
    mov si, msg_gzip_off
    call print
    ret
.enabled:
    mov si, msg_gzip_on
    call print
    ret
cmd_zip_exec:
    ; Create zip (show file count)
    mov si, msg_zip_creating
    call print
    mov ax, [vfs_file_count]
    mov al, al
    call print_num
    mov si, msg_zip_files
    call print
    ret
cmd_mount_exec:
    ; Toggle mounted flag
    xor byte [fs_mounted], 1
    cmp byte [fs_mounted], 1
    je .mounted
    mov si, msg_umount
    call print
    ret
.mounted:
    mov si, msg_mount
    call print
    ret
cmd_umount_exec:
    ; Unmount filesystem
    mov byte [fs_mounted], 0
    mov si, msg_umount
    call print
    ret
cmd_fdisk_exec:
    ; Show disk info
    mov si, msg_fdisk_header
    call print
    mov si, msg_fdisk_disk
    call print
    mov ax, [vfs_file_count]
    mov bx, 192
    mul bx
    shr ax, 10
    mov al, al
    call print_num
    mov si, msg_fdisk_kb
    call print
    ret
cmd_mkfs_exec:
    ; Format filesystem (clear all files)
    mov si, msg_mkfs_warning
    call print
    
    ; Clear file table
    mov di, file_table
    mov cx, MAX_FILES * 192
    xor al, al
    rep stosb
    
    ; Recreate directories
    call vfs_create_root_dirs
    mov word [vfs_file_count], 5
    
    mov si, msg_mkfs_done
    call print
    ret
cmd_fsck_exec:
    ; Check filesystem integrity
    mov si, msg_fsck_checking
    call print
    
    ; Count valid files
    xor bx, bx
    mov cx, [vfs_file_count]
    mov di, file_table
    
.check_loop:
    push cx
    cmp byte [di], 0
    je .skip
    inc bx
.skip:
    add di, 192
    pop cx
    loop .check_loop
    
    mov si, msg_fsck_found
    call print
    mov al, bl
    call print_num
    mov si, msg_fsck_files
    call print
    ret
cmd_su_exec:
    ; Switch user - toggle current UID
    mov al, [current_uid]
    cmp al, UID_ROOT
    je .to_user
    mov byte [current_uid], UID_ROOT
    mov si, msg_su_root
    call print
    ret
.to_user:
    mov byte [current_uid], UID_USER
    mov si, msg_su_user
    call print
    ret
cmd_sudo_exec:
    ; Temporarily elevate to root
    mov byte [current_uid], UID_ROOT
    mov si, msg_sudo_elevated
    call print
    ret
cmd_passwd_exec:
    ; Change password (simulated)
    mov si, msg_passwd_prompt
    call print
    
    ; "Read" password (just wait for key)
    mov ah, 0x00
    int 0x16
    
    mov si, msg_passwd_changed
    call print
    ret
cmd_chgrp_exec:
    ; Change group (UID) of last file
    cmp word [vfs_file_count], 0
    je .error
    
    mov ax, [vfs_file_count]
    dec ax
    mov bx, 192
    mul bx
    mov di, file_table
    add di, ax
    add di, 33  ; UID offset
    
    ; Toggle UID between root and user
    mov al, [di]
    cmp al, UID_ROOT
    je .set_user
    mov byte [di], UID_ROOT
    jmp .done
.set_user:
    mov byte [di], UID_USER
.done:
    mov si, msg_chgrp
    call print
    ret
    
.error:
    mov si, msg_chgrp_err
    call print
    ret
cmd_ln_exec:
    ; Create a link (copy) to last file
    cmp word [vfs_file_count], MAX_FILES - 1
    jge .full
    cmp word [vfs_file_count], 0
    je .no_files
    
    ; Copy last file
    mov ax, [vfs_file_count]
    dec ax
    mov bx, 192
    mul bx
    mov si, file_table
    add si, ax
    
    mov ax, [vfs_file_count]
    mov bx, 192
    mul bx
    mov di, file_table
    add di, ax
    
    ; Copy and mark as link
    mov cx, 192
    rep movsb
    
    inc word [vfs_file_count]
    mov si, msg_ln
    call print
    ret
    
.full:
    mov si, msg_fs_full
    call print
    ret
    
.no_files:
    mov si, msg_ln_err
    call print
    ret
cmd_stat_exec:
    ; Show real file stats for last file
    cmp word [vfs_file_count], 0
    je .error
    
    mov ax, [vfs_file_count]
    dec ax
    mov bx, 192
    mul bx
    mov di, file_table
    add di, ax
    
    ; Print file name
    mov si, msg_stat_file
    call print
    mov si, di
    call print
    mov si, msg_newline
    call print
    
    ; Print type
    mov si, msg_stat_type
    call print
    mov al, [di+32]
    test al, al
    jz .type_file
    mov si, str_type_dir
    jmp .print_type
.type_file:
    mov si, str_type_file
.print_type:
    call print
    mov si, msg_newline
    call print
    
    ; Print UID
    mov si, msg_stat_uid
    call print
    mov al, [di+33]
    call print_num
    mov si, msg_newline
    call print
    
    ; Print permissions
    mov si, msg_stat_perms
    call print
    mov al, [di+34]
    call print_octal
    mov si, msg_newline
    call print
    
    ; Print size
    mov si, msg_stat_size
    call print
    mov ax, [di+35]
    mov al, ah
    call print_num
    mov si, msg_newline
    call print
    ret
    
.error:
    mov si, msg_stat_err
    call print
    ret
cmd_du_exec:
    ; Show disk usage - count files and total size
    mov cx, [vfs_file_count]
    mov si, msg_du_files
    call print
    mov al, cl
    call print_num
    mov si, msg_newline
    call print
    
    ; Estimate size (files * 192)
    mov ax, cx
    mov bx, 192
    mul bx
    shr ax, 10  ; Convert to KB
    mov si, msg_du_size
    call print
    call print_num
    mov si, msg_du_kb
    call print
    ret
cmd_man_exec:
    mov si, msg_man
    call print
    ret
cmd_which_exec:
    ; Show command location
    cmp byte [cmd_args], 0
    je .no_args
    
    ; Check if command exists in our command list
    mov si, cmd_args
    mov di, cmd_ls
    call strcmp
    jz .found
    mov di, cmd_pwd
    call strcmp
    jz .found
    mov di, cmd_cat
    call strcmp
    jz .found
    mov di, cmd_ps
    call strcmp
    jz .found
    
    ; Not found
    mov si, msg_which_notfound
    call print
    ret
    
.found:
    mov si, msg_which_found
    call print
    ret
    
.no_args:
    mov si, msg_which_noargs
    call print
    ret
cmd_alias_exec:
    ; Show/set aliases
    cmp byte [cmd_args], 0
    je .show_aliases
    
    ; Set alias (just acknowledge)
    mov si, msg_alias_set
    call print
    ret
    
.show_aliases:
    mov si, msg_alias_list
    call print
    ret
cmd_history_exec:
    ; Show command history (last 5 commands)
    mov si, msg_history_header
    call print
    
    mov cx, 5
    xor bx, bx
.show:
    push cx
    push bx
    
    ; Print number
    mov al, bl
    inc al
    call print_num
    mov si, msg_space
    call print
    
    ; Show command (just show ls as example)
    mov si, str_hist_cmd
    call print
    mov si, msg_newline
    call print
    
    pop bx
    inc bx
    pop cx
    loop .show
    ret
cmd_export_exec:
    ; Set environment variable
    cmp byte [cmd_args], 0
    je .show_env
    
    ; Parse VAR=value (simplified - just store arg)
    mov si, cmd_args
    mov di, env_var
    mov cx, 32
    rep movsb
    
    mov si, msg_export_set
    call print
    ret
    
.show_env:
    ; Show current env var
    mov si, msg_export_var
    call print
    mov si, env_var
    call print
    mov si, msg_newline
    call print
    ret
cmd_source_exec:
    mov si, msg_source
    call print
    ret

; Parse command arguments
; Splits cmd_buf into command and arguments
parse_cmd_args:
    push si
    push di
    push cx
    
    ; Find first space
    mov si, cmd_buf
    mov di, cmd_args
    xor cx, cx
    
.find_space:
    lodsb
    test al, al
    jz .no_args
    cmp al, ' '
    je .found_space
    jmp .find_space
    
.found_space:
    ; Copy rest to cmd_args
.copy_args:
    lodsb
    stosb
    test al, al
    jnz .copy_args
    jmp .done
    
.no_args:
    ; No arguments
    mov byte [cmd_args], 0
    
.done:
    pop cx
    pop di
    pop si
    ret

; ========================================
; UTILITIES
; ========================================

show_boot:
    mov si, banner
    call print
    mov si, boot_msg
    call print
    ret

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
    je .back
    cmp al, 0x20
    jl .loop
    cmp cx, 60
    jge .loop
    mov ah, 0x0E
    int 0x10
    stosb
    inc cx
    jmp .loop
.back:
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

strcmp:
    push si
    push di
.loop:
    lodsb
    mov bl, [di]
    inc di
    cmp al, bl
    jne .no
    test al, al
    jz .yes
    jmp .loop
.yes:
    pop di
    pop si
    xor ax, ax
    ret
.no:
    pop di
    pop si
    mov ax, 1
    ret

; Print number (AL = number)
print_num:
    push ax
    push bx
    push cx
    push dx
    
    xor ah, ah
    mov bl, 10
    xor cx, cx
    
.divide:
    xor dx, dx
    div bl
    push dx
    inc cx
    test al, al
    jnz .divide
    
.print_digits:
    pop dx
    add dl, '0'
    mov ah, 0x0E
    mov al, dl
    int 0x10
    loop .print_digits
    
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Print octal (AL = number)
print_octal:
    push ax
    push bx
    
    mov bl, al
    shr bl, 6
    and bl, 7
    add bl, '0'
    mov ah, 0x0E
    mov al, bl
    int 0x10
    
    pop bx
    push bx
    mov bl, al
    shr bl, 3
    and bl, 7
    add bl, '0'
    mov ah, 0x0E
    mov al, bl
    int 0x10
    
    pop bx
    and bl, 7
    add bl, '0'
    mov ah, 0x0E
    mov al, bl
    int 0x10
    
    pop ax
    ret

; ========================================
; DATA
; ========================================

debug_start: db 'K122A LOADING...', 13, 10, 0

banner:
    db '================================================', 13, 10
    db '  K122A v1.0 - Unix-like Kernel', 13, 10
    db '================================================', 13, 10, 0

boot_msg:
    db '[OK] VFS initialized', 13, 10
    db '[OK] Process manager ready', 13, 10
    db '[OK] 11 processes loaded', 13, 10
    db '[OK] Filesystem mounted', 13, 10
    db '[OK] System ready', 13, 10, 13, 10, 0

prompt: db 'root@k122a:/# ', 0

; Directory names
str_system: db 'system', 0
str_etc: db 'etc', 0
str_home: db 'home', 0
str_dev: db 'dev', 0
str_sys: db 'sys', 0

; File names
str_system_kernel: db 'system/kernel.bin', 0

; File data
data_kernel: db 'K122A Kernel Binary v1.0', 0

; Commands
cmd_ls: db 'ls', 0
cmd_pwd: db 'pwd', 0
cmd_cat: db 'cat', 0
cmd_help: db 'help', 0
cmd_ps: db 'ps', 0
cmd_mkdir: db 'mkdir', 0
cmd_touch: db 'touch', 0
cmd_rm: db 'rm', 0
cmd_echo: db 'echo', 0
cmd_clear: db 'clear', 0
cmd_cd: db 'cd', 0
cmd_uname: db 'uname', 0
cmd_whoami: db 'whoami', 0
cmd_chmod: db 'chmod', 0
cmd_kill: db 'kill', 0
cmd_cp: db 'cp', 0
cmd_mv: db 'mv', 0
cmd_df: db 'df', 0
cmd_free: db 'free', 0
cmd_uptime: db 'uptime', 0
cmd_date: db 'date', 0
cmd_hostname: db 'hostname', 0
cmd_reboot: db 'reboot', 0
cmd_halt: db 'halt', 0
cmd_grep: db 'grep', 0
cmd_find: db 'find', 0
cmd_wc: db 'wc', 0
cmd_head: db 'head', 0
cmd_tail: db 'tail', 0
cmd_env: db 'env', 0
cmd_top: db 'top', 0
cmd_vmstat: db 'vmstat', 0
cmd_dmesg: db 'dmesg', 0
cmd_lsof: db 'lsof', 0
cmd_netstat: db 'netstat', 0
cmd_ifconfig: db 'ifconfig', 0
cmd_ping: db 'ping', 0
cmd_wget: db 'wget', 0
cmd_curl: db 'curl', 0
cmd_tar: db 'tar', 0
cmd_gzip: db 'gzip', 0
cmd_zip: db 'zip', 0
cmd_mount: db 'mount', 0
cmd_umount: db 'umount', 0
cmd_fdisk: db 'fdisk', 0
cmd_mkfs: db 'mkfs', 0
cmd_fsck: db 'fsck', 0
cmd_su: db 'su', 0
cmd_sudo: db 'sudo', 0
cmd_passwd: db 'passwd', 0
cmd_chgrp: db 'chgrp', 0
cmd_ln: db 'ln', 0
cmd_stat: db 'stat', 0
cmd_du: db 'du', 0
cmd_man: db 'man', 0
cmd_which: db 'which', 0
cmd_alias: db 'alias', 0
cmd_history: db 'history', 0
cmd_export: db 'export', 0
cmd_source: db 'source', 0

; Messages
msg_unknown: db 'Command not found', 13, 10, 0
msg_ls_header: db 13, 10, 0
msg_dir_indicator: db '/', 13, 10, 0
msg_newline: db 13, 10, 0
msg_root: db '/', 13, 10, 0
msg_cat_notfound: db 'File not found', 13, 10, 0
msg_space: db ' ', 0
msg_cd_err: db 'Directory not found', 13, 10, 0
msg_cd_current: db 'Current dir: ', 0
msg_stat_file: db 'File: ', 0
msg_stat_type: db 'Type: ', 0
msg_stat_uid: db 'UID: ', 0
msg_stat_perms: db 'Perms: ', 0
msg_stat_size: db 'Size: ', 0
msg_stat_err: db 'No file to stat', 13, 10, 0
msg_chgrp_err: db 'Cannot change group', 13, 10, 0
str_type_file: db 'file', 0
str_type_dir: db 'directory', 0
msg_colon: db ': ', 0
msg_grep_noargs: db 'Usage: grep <text>', 13, 10, 0
msg_wc_bytes: db 'Total bytes: ', 0
msg_du_files: db 'Files: ', 0
msg_du_size: db 'Size: ', 0
msg_du_kb: db ' KB', 13, 10, 0
msg_top_header: db 'TOP - Process Monitor', 13, 10, 0
msg_top_vfs: db 'VFS ops: ', 0
msg_top_sched: db 'Sched ticks: ', 0
msg_top_tty: db 'TTY chars: ', 0
msg_top_running: db 'Running: ', 0
msg_top_total: db ' / ', 0
msg_ln_err: db 'No files to link', 13, 10, 0
msg_which_found: db '/bin/', 0
msg_which_notfound: db 'Command not found', 13, 10, 0
msg_which_noargs: db 'Usage: which <cmd>', 13, 10, 0
msg_history_header: db 'Command History:', 13, 10, 0
str_hist_cmd: db 'ls', 0
msg_alias_list: db 'alias ll=ls -la', 13, 10, 0
msg_alias_set: db 'Alias set', 13, 10, 0
msg_export_set: db 'Variable exported', 13, 10, 0
msg_export_var: db 'ENV: ', 0
msg_su_root: db 'Switched to root', 13, 10, 0
msg_su_user: db 'Switched to user', 13, 10, 0
msg_sudo_elevated: db 'Running as root', 13, 10, 0
msg_passwd_prompt: db 'New password: ', 0
msg_passwd_changed: db 'Password updated', 13, 10, 0
msg_ifconfig_header: db 'Network Interfaces:', 13, 10, 0
msg_ifconfig_lo: db 'lo0: ', 0
msg_ifconfig_up: db 'UP 127.0.0.1', 13, 10, 0
msg_ifconfig_down: db 'DOWN', 13, 10, 0
msg_ping_reply: db 'PING 127.0.0.1: OK', 13, 10, 0
msg_ping_fail: db 'Network unreachable', 13, 10, 0
msg_head_err: db 'No files', 13, 10, 0
msg_tail_err: db 'No files', 13, 10, 0
msg_tar_creating: db 'Creating archive with ', 0
msg_tar_files: db ' files', 13, 10, 0
msg_gzip_on: db 'Compression enabled', 13, 10, 0
msg_gzip_off: db 'Compression disabled', 13, 10, 0
msg_zip_creating: db 'Zipping ', 0
msg_zip_files: db ' files', 13, 10, 0
msg_wget_ok: db 'Downloaded successfully', 13, 10, 0
msg_curl_response: db 'HTTP/1.1 200 OK', 13, 10, 0
msg_curl_err: db 'Connection failed', 13, 10, 0
msg_fdisk_header: db 'Disk Information:', 13, 10, 0
msg_fdisk_disk: db '/dev/ram0: ', 0
msg_fdisk_kb: db ' KB', 13, 10, 0
msg_mkfs_warning: db 'Formatting filesystem...', 13, 10, 0
msg_mkfs_done: db 'Filesystem created', 13, 10, 0
msg_fsck_checking: db 'Checking filesystem...', 13, 10, 0
msg_fsck_found: db 'Found ', 0
msg_fsck_files: db ' valid files', 13, 10, 0
msg_vmstat_header: db 'Memory Statistics:', 13, 10, 0
msg_vmstat_used: db 'Used: ', 0
msg_vmstat_kb: db ' KB', 13, 10, 0
msg_dmesg_boot: db '[0.000] K122A boot', 13, 10, 0
msg_dmesg_vfs: db '[0.001] VFS ready', 13, 10, 0
msg_dmesg_proc: db '[0.002] Proc ready', 13, 10, 0
msg_lsof_header: db 'Open Files:', 13, 10, 0
msg_lsof_file: db ' /dev/tty', 13, 10, 0
msg_netstat_header: db 'Network Connections:', 13, 10, 0
msg_netstat_none: db 'No connections', 13, 10, 0
msg_netstat_active: db 'lo0: ESTABLISHED', 13, 10, 0

help_text:
    db 'K122A - ALL 60 COMMANDS READY!', 13, 10
    db '  ls pwd cat ps mkdir touch rm cp mv', 13, 10
    db '  echo clear cd uname whoami chmod kill', 13, 10
    db '  df free uptime date hostname reboot halt', 13, 10
    db '  grep find wc head tail env top vmstat', 13, 10
    db '  dmesg lsof netstat ifconfig ping wget', 13, 10
    db '  curl tar gzip zip mount umount fdisk', 13, 10
    db '  mkfs fsck su sudo passwd chgrp ln stat', 13, 10
    db '  du man which alias history export source', 13, 10
    db 'Type any command! Type help for this list', 13, 10, 0

ps_header:
    db 'PID PPID CPU% MEM STATE NAME', 13, 10, 0
ps_space: db ' ', 0
ps_percent: db '% ', 0
ps_kb: db 'K ', 0
ps_state_run: db 'RUN', 0
ps_state_sleep: db 'SLP', 0

; Process names
proc_name_init: db 'init', 0
proc_name_sched: db 'sched', 0
proc_name_vfs: db 'vfs', 0
proc_name_mem: db 'memory', 0
proc_name_net: db 'network', 0
proc_name_tty: db 'tty', 0
proc_name_disk: db 'disk', 0
proc_name_app1: db 'app1', 0
proc_name_app2: db 'app2', 0
proc_name_app3: db 'app3', 0
proc_name_shell: db 'bash', 0

; More messages
msg_mkdir_ok: db 'Directory created', 13, 10, 0
msg_touch_ok: db 'File created', 13, 10, 0
msg_rm_ok: db 'Removed', 13, 10, 0
msg_rm_err: db 'Cannot remove', 13, 10, 0
msg_echo_out: db 'Hello from K122A!', 13, 10, 0
msg_cd_ok: db 'Directory changed', 13, 10, 0
msg_uname: db 'K122A v1.0 x86_16', 13, 10, 0
msg_whoami: db 'root', 13, 10, 0
msg_chmod_ok: db 'Permissions changed', 13, 10, 0
msg_kill_ok: db 'Process terminated', 13, 10, 0
msg_kill_err: db 'Cannot kill process', 13, 10, 0
msg_kill_already: db 'Process already dead', 13, 10, 0
msg_chmod_err: db 'Cannot change permissions', 13, 10, 0
msg_mv_err: db 'Cannot move file', 13, 10, 0
msg_fs_full: db 'Filesystem full', 13, 10, 0

str_newdir: db 'newdir', 0
str_newfile: db 'newfile.txt', 0
str_moved: db 'moved', 0
str_downloaded: db 'index.html', 0

msg_cp_ok: db 'File copied', 13, 10, 0
msg_mv_ok: db 'File moved', 13, 10, 0
msg_df:
    db 'Filesystem   Size  Used Avail', 13, 10
    db '/dev/ram0    64K   16K   48K', 13, 10, 0
msg_free:
    db 'Total: 640K Used: 192K Free: 448K', 13, 10, 0
msg_uptime: db 'up 0 days, 0:12', 13, 10, 0
msg_date: db 'Mon Oct 15 09:45:00 UTC 2025', 13, 10, 0
msg_hostname: db 'k122a-kernel', 13, 10, 0
msg_rebooting: db 'Rebooting system...', 13, 10, 0
msg_halting: db 'System halted.', 13, 10, 0
msg_grep: db 'grep: pattern matching', 13, 10, 0
msg_find: db 'find: searching files', 13, 10, 0
msg_wc: db 'lines: 42 words: 256 bytes: 1024', 13, 10, 0
msg_head: db 'K122A Kernel', 13, 10, 'First lines', 13, 10, 0
msg_tail: db 'Last lines', 13, 10, 'End of file', 13, 10, 0
msg_env:
    db 'PATH=/bin:/usr/bin', 13, 10
    db 'USER=root', 13, 10
    db 'SHELL=/bin/bash', 13, 10, 0

; Final 30 messages
msg_top: db 'CPU: 5% MEM: 30% PROCS: 11', 13, 10, 0
msg_vmstat: db 'mem: 640K swap: 0K', 13, 10, 0
msg_dmesg: db '[0.001] K122A boot', 13, 10, 0
msg_lsof: db 'PID 11: /dev/tty', 13, 10, 0
msg_netstat: db 'No network active', 13, 10, 0
msg_ifconfig: db 'lo0: UP 127.0.0.1', 13, 10, 0
msg_ping: db 'PING 127.0.0.1: alive', 13, 10, 0
msg_wget: db 'wget: download ready', 13, 10, 0
msg_curl: db 'curl: HTTP client', 13, 10, 0
msg_tar: db 'tar: archive tool', 13, 10, 0
msg_gzip: db 'gzip: compressed', 13, 10, 0
msg_zip: db 'zip: created', 13, 10, 0
msg_mount: db 'Mounted /dev/ram0', 13, 10, 0
msg_umount: db 'Unmounted', 13, 10, 0
msg_fdisk: db 'Disk /dev/ram0: 64K', 13, 10, 0
msg_mkfs: db 'Filesystem created', 13, 10, 0
msg_fsck: db 'FS check: OK', 13, 10, 0
msg_su: db 'Switched user', 13, 10, 0
msg_sudo: db 'Running as root', 13, 10, 0
msg_passwd: db 'Password updated', 13, 10, 0
msg_chgrp: db 'Group changed', 13, 10, 0
msg_ln: db 'Link created', 13, 10, 0
msg_stat: db 'Size: 1024 UID: 0', 13, 10, 0
msg_du: db 'Total: 16K', 13, 10, 0
msg_man: db 'Manual: K122A v1.0', 13, 10, 0
msg_which: db '/bin/ls', 13, 10, 0
msg_alias: db 'alias ll=ls', 13, 10, 0
msg_history: db '1: ls', 13, 10, '2: ps', 13, 10, 0
msg_export: db 'Variable exported', 13, 10, 0
msg_source: db 'Script sourced', 13, 10, 0

; VFS data
vfs_file_count: dw 0
vfs_current_dir: db 0
fs_mounted: db 1
cmd_buf: times 64 db 0
cmd_args: times 64 db 0

; Process data
proc_count: dw 0

; User data
current_uid: db 0
net_enabled: db 1
compression_enabled: db 0
env_var: times 32 db 0

; File table: Each entry 192 bytes
; [0-31]   Name (32 bytes)
; [32]     Type (0=file, 1=dir)
; [33]     UID
; [34]     Permissions
; [35-36]  Size
; [64-191] Data (128 bytes)
file_table: times (MAX_FILES * 192) db 0

; Process table: Each entry 64 bytes
; [0]    PID
; [1]    UID
; [2]    State (0=sleep, 1=run, 2=zombie)
; [3]    CPU usage %
; [4-5]  Name pointer
; [6-7]  Parent PID
; [8-9]  Memory used (KB)
; [10]   Priority
proc_table: times (MAX_PROCS * 64) db 0

; Process statistics
proc_stats:
    file_ops: dw 0        ; VFS operations
    sched_ticks: dw 0     ; Scheduler ticks
    mem_allocs: dw 0      ; Memory allocations
    net_packets: dw 0     ; Network packets
    disk_reads: dw 0      ; Disk operations
    tty_chars: dw 0       ; TTY characters

times 20992-($-$$) db 0  ; Pad to 41 sectors
