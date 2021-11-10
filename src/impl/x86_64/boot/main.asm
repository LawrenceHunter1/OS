global start
extern long_mode_start

section .text
bits 32
start:
	mov esp, stack_top

	call check_multiboot
	call check_cpuid
	call check_long_mode
	
	; need to setup paging 
	call setup_page_tables
	call enable_paging

	lgdt [gdt64.pointer] ; load table
	jmp gdt64.code_segment:long_mode_start ; load code segment jump to 64bit assembly

	hlt


check_multiboot:
	cmp eax, 0x36d76289
	jne .no_multiboot
	ret
.no_multiboot:
	mov al, "M"
	jmp error

check_cpuid:
	; attempt to flip id bit register
	pushfd
	pop eax
	mov ecx, eax
	xor eax, 1 << 21
	push eax
	popfd
	pushfd
	pop eax
	push ecx
	popfd
	cmp eax, ecx
	je .no_cpuid
	ret
.no_cpuid:
	mov al, "C"
	jmp error

check_long_mode:
	; +1 if cpu supports extended processor info
	mov eax, 0x80000000
	cpuid
	cmp eax, 0x80000001
	jb .no_long_mode

	; sets bit 29 if long mode is availabe
	mov eax, 0x80000001
	cpuid
	test edx, 1 << 29
	jz .no_long_mode

	ret
.no_long_mode:
	mov al, "L"
	jmp error

setup_page_tables:
	mov eax, page_table_l3
	or eax, 0b11 ; present, writable
	mov [page_table_l4], eax

	mov eax, page_table_l2
	or eax, 0b11 ; present, writable
	mov [page_table_l3], eax

	mov ecx, 0
.loop:
	mov eax, 0x200000 ; 2MiB
	mul ecx
	or eax, 0b10000011 ; present, writable, huge
	mov [page_table_l2 + ecx * 8], eax

	inc ecx ; increment counter
	cmp ecx, 512 ; is whole page mapped
	jne .loop

	ret

enable_paging:
	; pass page table location
	mov eax, page_table_l4
	mov cr3, eax

	; enable PAE
	mov eax, cr4
	or eax, 1 << 5
	mov cr4, eax

	; enable long mode
	mov ecx, 0xC0000080
	rdmsr ; read model specific register
	or eax, 1 << 8
	wrmsr ; write model specific register

	; enable paging
	mov eax, cr0
	or eax, 1 << 31
	mov cr0, eax
	ret

error:
	; prints "ERR: X" where X is the error code
	mov dword [0xb8000], 0x4f524f45
	mov dword [0xb8004], 0x4f3a4f52
	mov dword [0xb8008], 0x4f204f20
	mov byte  [0xb800a], al
	hlt

section .bss
; 3 page tables each 4KB aligned
align 4096
page_table_l4:
	resb 4096
page_table_l3:
	resb 4096
page_table_l2:
	resb 4096

; reserve 4KB for stack
stack_bottom:
	resb 4096 * 4
stack_top:

section .rodata
gdt64:
	dq 0 ; zero entry
.code_segment: equ $ - gdt64 ; need offset of table
	dq (1 << 43) | (1 << 44) | (1 << 47) | (1 << 53); enable ex flag, set descriptor type code and data segments, enable present flag, enable 64 bit flag
.pointer: ; pointer to script table
	; $ current address
	dw $ - gdt64 - 1 ; 2 byte pointer current address minus table 
	dq gdt64 ; store pointer itself