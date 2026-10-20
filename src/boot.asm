[BITS 16]
[ORG 0x7c00]

CODE_OFF equ 0x08
DATA_OFF equ 0x10

start:
    mov [boot_drive], dl        ; store our boot drive number
    cli                         ; stop certain interrupts by setting interrupts flag = 0

    xor ax, ax
    mov ds, ax                  ; zero out the segment registers...no you can't xor them
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00              ; stack grows from 0x7c00 to 0x0, code goes from 0x7c00 to 0x7e00 (512 bytes)

    ;; unlock the A20 line, this allows usage of 1MiB+ memory
    in al, 0x92                 ; load motherboard data into al, through port 0x92
    or al, 2                    ; flip the first bit
    out 0x92, al                ; send back to motherboard, through port 0x92

    sti                         ; opposite of cli set interrupts flag = 1
    ;; mov si, msg

;; print: 
;;     lodsb                       ; load byte by byte from data segment (ds) into al using si (ds:si)
;;     cmp al, 0                   ; check if character is a null byte
;;     je done
;;     mov ah, 0x0e                ; 0x0e = write character in tty
;;     int 0x10                    ; video interrupt
;;     jmp print

done:   

    ;; load the kernel headers to a scratch buffer
    mov ah, 0x42                ; perform LBA instead of CHS
    mov si, dap                 ; our dap, hardcoded for kernel headers
    mov dl, [boot_drive]
    int 0x13                    ; go go gadget bios interrupt

    jmp load_PM

;; msg:
;;     db "LOADBOOTER", 0

load_PM:    
    cli
    ;; zero out 4096 bytes starting at 0x90000 (our zero page)
    ;; addr = segment * 16 + offset = segment:offset
    mov ax, 0x9000
    mov es, ax                  ; segment
    xor di, di                  ; di = 0x0
    xor al, al                  ; al = 0 => value to fill
    mov cx, 0x1000              ; 4096 bytes
    cld                         ; increment es:di by incrementing di
    rep stosb                   ; magic, uses es:di, which equals 0x90000

    xor ebx, ebx                ; start from the first entry
    xor bp, bp                  ; number of entries

    ;; load kernel headers from scratch buffer to zero page
    ;; rep movsb, copies from DS:SI to ES:DI, runs cx times
    mov ax, 0x9200
    mov ds, ax
    mov si, 0x1f1
    mov ax, 0x9000
    mov di, 0x1f1
    mov es, ax
    movzx cx, byte [0x201]      ; set to header length
    add cx, 0x11                ; maths, idk
    cld 
    rep movsb

    ;; extra addition to our zero page
    mov byte [es:0x210], 0xff
    mov dword [es:0x228], cmdline
    mov di, 0x2d0               ; reset di back to 0x2d0 for e820_next

;; the glorious e820 process
e820_next:  
    mov eax, 0xe820             ; the memory map function thing
    mov ecx, 20                 ; get a 20 byte structure
    mov edx, 0x534D4150         ; apparently SMAP is required in edx
    int 0x15                    ; call the bios
    jc e820_done                ; carry flag => done, probably (skull emoji)
    cmp eax, 0x534D4150         ; SMAP
    jne crash                   ; idk just ud2 ts not doing a whole print thing

    ;; check if the entry is empty
    mov eax, [es:di + 8]
    or eax, [es:di + 12]
    jz e820_skip
    
    inc bp                      ; increment our total entry count by 1
    add di, 20                  ; next entry offset
    cmp bp, 128                 ; total 128 entries
    jae e820_done

e820_skip:  
    test ebx, ebx               ; ebx = 0 => it was the last entry
    jnz e820_next

e820_done:  
    test bp, bp
    jz crash                    ; no entries => something must be wrong
    mov ax, bp
    mov [es:0x1e8], al

    xor ax, ax
    mov ds, ax
    mov es, ax
    lgdt[gdt_descriptor]        ; loads pointer to gdt in GDTR register
    mov eax, cr0
    or al, 1
    mov cr0, eax                ; set first bit of cr0 = 1, we going protected mode gng
    jmp CODE_OFF:PModeMain

;; gdt - global descriptor table is a table that defines characterestics of segments like base addr, size (limit) and permissions
;; notes: https://wiki.osdev.org/Global_Descriptor_Table
gdt_start:  
    ;; null entry
    dd 0x0
    dd 0x0

    ;; ;; another null entry
    ;; dd 0x0
    ;; dd 0x0

    ;; code segment descriptor 
    dw 0xFFFF                   ; limit
    dw 0x0000                   ; base
    db 0x00                     ; base 2
    db 10011010b                ; access byte
    db 11001111b                ; flags
    db 0x00                     ; base

    ;; data segment descriptor 
    dw 0xFFFF                   ; limit
    dw 0x0000                   ; base
    db 0x00                     ; base 2
    db 10010010b                ; access byte
    db 11001111b                ; flags
    db 0x00                     ; base
gdt_end:

;; a disk address packet, data structure that stores what and where of disk access
dap:
    db 16, 0                       ; size of our dap
dap_count:  dw 2                   ; how many sectors to read (bios only max 127 at once!)
dap_off:    dw 0x0                 ; offset to read
dap_seg:    dw 0x9200              ; segment to read
dap_lba:    dd 4, 0                ; idk what this means either

;; to store our drive number
boot_drive: db 0

;; it is exactly what it looks like
cmdline: db "console=ttyS0 earlyprintk=serial,ttyS0", 0

gdt_descriptor: 
    dw gdt_end - gdt_start - 1  ; size of gdt - 1
    dd gdt_start
crash:  
    ud2

[BITS 32]
PModeMain:
    ;; setup stack and shi
    mov ax, DATA_OFF
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov ss, ax
    mov gs, ax
    mov ebp, 0x9c00
    mov esp, ebp

    xor edx, edx
    ;; disk read using ATA LBA shit i don't understand but it works
    push 1922                   ; hardcoded number of sectors
    pop ecx
    mov edi, 0x100000           ; store at this addr

    mov dx, 0x1f6
    mov al, 0x40
    out dx, al

    mov dl, 0xf2
    mov al, 0x07
    out dx, al
    mov al, 0x82
    out dx, al

    mov eax, 0x2400
    mov dl, 0xf3
    out dx, al
    shr eax, 8
    out dx, al
    xor al, al
    inc edx
    out dx, al
    out dx, al
    inc edx
    out dx, al
    out dx, al

    mov dl, 0xf7
    mov al, 0x24
    out dx, al
    
    ;; shl ecx, 8
    ;; mov dl, 0xf0
    ;; rep insw

;; apparently this kind of polling setup is required or else shit just won't work
sector: 
    mov dl, 0xf7
drq:
    in al, dx
    test al, 8
    jz drq 
    mov dl, 0xf0
    push ecx
    mov ecx, 256
    rep insw
    pop ecx
    loop sector
    mov esi, 0x90000
    mov eax, 0x100000
    jmp eax

    ;; mov esi, 0x90000
    ;; mov eax, 0x100000
    ;; jmp eax

times 510 - ($ - $$) db 0x67    ; fill the the rest bytes, as bios needs to be 512 bytes (0aa55 is 2 bytes so using 510)

dw 0xaa55                       ; the signature
