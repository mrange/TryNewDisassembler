; dotnet core 3.1

; PushStream.fromRange  0 x.Count
LOOP:
mov     rcx,rsi
mov     edx,edi
mov     rax,qword ptr [rsi]
mov     rax,qword ptr [rax+40h]
call    qword ptr [rax+20h]
inc     edi
cmp     edi,ebx
jne     LOOP

; PushStream.map     int64
nop     dword ptr [rax+rax]
mov     rcx,qword ptr [rcx+8]
movsxd  rdx,edx
mov     rax,qword ptr [rcx]
mov     rax,qword ptr [rax+40h]
mov     rax,qword ptr [rax+20h]
jmp     rax

; PushStream.filter  (fun v -> (v &&& 1L) = 0L)
nop     dword ptr [rax+rax]
mov     eax,edx
test    al,1
jne     BAILOUT
mov     rcx,qword ptr [rcx+8]
mov     rax,qword ptr [rcx]
mov     rax,qword ptr [rax+40h]
mov     rax,qword ptr [rax+20h]
jmp     rax
BAILOUT:
xor     eax,eax
ret

; PushStream.map     ((+) 1L)
nop     dword ptr [rax+rax]
mov     rcx,qword ptr [rcx+8]
inc     rdx
mov     rax,qword ptr [rcx]
mov     rax,qword ptr [rax+40h]
mov     rax,qword ptr [rax+20h]
jmp     rax

; PushStream.sum
nop     dword ptr [rax+rax]
mov     rax,qword ptr [rcx+8]
mov     rcx,rax
add     rdx,qword ptr [rax+8]
mov     qword ptr [rcx+8],rdx
xor     eax,eax
ret

