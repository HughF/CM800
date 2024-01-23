TITLE	SONAR5V5

	;select which version is to be assembled
	;note: if demo=2, no picture is loaded
	;if replay=2, only the PC keyboard is used


DOS	equ 1
REPLAY	equ 0
DEMO	equ 0

HIPOWER     equ 0

EGS	equ 0				;print nav in the middle
PSEA	equ 0				;only valid is DOS=1
FAKENAV equ 0
FORCEEXPORT equ 0
CONTDESK    equ 1			;1 for cont deskjet, otherwize 2
MOUSEPORT   equ 0			;1 is ps/2 mouse is enabled

NULLPRINTER equ 0
SLOWPRINT   equ 0

FISHTYPE    equ 0			;1=HF ranges only
DISKLESS    equ 0

MICREL	equ 0
NOOFBITS    equ 02			;02 for 7 bit, 06 for 8 bit

DOSINTMASK	equ 11000001b
REPINTMASK	equ 11101001b
		   ;PFSMNCKT
		   ;RLOOAAEI
		   ;IONUVSYM
		   ;NPAS CBE
		   ;TPRE AOO
		   ;EY	 DAU
		   ;R	 ERT
		   ;	  D

VersionString equ <'5.5'>


	;optical disk drive settings
	;SCSI-1 mode
	;mac mode off (unit attn after reset or disk change)
	;write cache off

	;screen display is split up as follows:
	;0-51=status bar
	;normal mode
	; 52-479=active window
	;freeze mode
	; 52-112=active window
	; 113-114=dividing line
	; 115-479=freeze window

	IF DOS
	.486P			       ;WILL RUN ON A 486 or HIGHER
	ELSE
	.386P
	ENDIF

	OPTION NOKEYWORD:<ESC>	       ;remove 'ESC' from reserved words

ESC	equ 27
RecordChunk EQU 16
FlipOver    EQU 600
SCSIReg0    EQU 218H			;53C80 addresses
SCSIReg1    EQU 219H
SCSIReg2    EQU 21AH
SCSIReg3    EQU 21BH
SCSIReg4    EQU 21CH
SCSIReg5    EQU 21DH
SCSIReg6    EQU 21EH
SCSIReg7    EQU 21FH

DescriptorTable	STRUCT		       ;THE GDT and IDT ARE LOADED
Limit	word 0			       ;WITH A `DescriptorTable`
Address	dword 0
DescriptorTable	ENDS

SSEG	SEGMENT STACK USE16	       ;256 WORDS IS PLENTY
	word 0100H dup (?)	       ;For THE Real mode STACK
SSEG	ENDS

BiosSeg SEGMENT USE16 AT 40H	       ;segment for the BIOS data area

	ORG 06CH
TickCounter dword ?		       ;system timer count

BiosSeg ENDS


CSEG	SEGMENT READONLY USE16

	ASSUME CS:CSEG,DS:DSEG,FS:FSEG,GS:GSEG


BEGIN:

	mov BP,DSEG

	IF DEMO EQ 1

	mov es,bp
	cld
	;first copy filename from prefix
	mov si,80h
	movzx cx,byte ptr [si]		       ;filename length
	cmp cx,0
	jne @f
	mov ds,bp
	mov dx,offset SyntaxMsg
	mov ah,9
	int 21h
	mov ah,04ch
	int 21h
@@:
	dec cx
	add si,2
	mov di,offset FileName
	rep movsb
	ENDIF

	mov ds,bp

	IF DEMO EQ 1
	mov XMSTable,32768
	mov SourceOffset,offset TransferBuffer
	mov SourceSegment,ds
	ENDIF

	;first make sure it is in true real mode
	mov eax,cr0
	test al,1
	je @f
	;error-not in real mode
	mov dx,offset XMSErrorMsg3
	mov ah,9
	int 21h
	mov ah,04ch
	int 21h
@@:
	IF DOS or REPLAY
	mov dx,211h
	in al,dx
	and al,0f0h
	cmp al,0f0h
	jne @f
	;error-no controller card found
	mov dx,offset XMSErrorMsg4
	mov ah,9
	int 21h
	mov ah,04ch
	int 21h
@@:
	ENDIF

	mov ax,4300h		       ;see if XMS driver is installed
	int 2fh
	cmp al,80h
	je @f
	;error-no XMS driver
	mov dx,offset XMSErrorMsg1
	mov ah,9
	int 21h
	mov ah,04ch
	int 21h
@@:
	mov ax,4310h		       ;get XMS service address
	int 2fh

	mov HandlerSegment,es
	mov HandlerOffset,bx

	;check free extended memory
	mov ah,08h
	call dword ptr HandlerOffset
	cmp ax,1024			;enough for 1M buffer?
	jae @f
	;error-not enough extended memory
	mov dx,offset XMSErrorMsg2
	mov ah,9
	int 21h
	mov ah,04ch
	int 21h
@@:
	mov dx,1024		       ;1M
	cmp ax,2048
	jb @f
	mov dx,2048		       ;assume 2M
	cmp ax,4096		       ;enough for 4M buffer
	jb @f
	mov dx,4096
	cmp ax,8192		       ;enough for 4M buffer
	jb @f
	mov dx,8192		       ;request 4M buffer
@@:
	shr dx,2		       ;4k per scan
	mov bx,dx		       ;calculate LastSelector
	add bx,7
	shl bx,3
	mov LastSelector,bx
	mov BufferSize,dx
	dec dx
	mov BufferLimit,dx
	inc dx
	mov ah,09h		       ;request dxK of extended memory
	call dword ptr HandlerOffset
	;handle in dx
	mov XMSHandle,dx
	mov ah,0ch		       ;lock XMS block and get
	call dword ptr HandlerOffset   ;address
	shrd bx,dx,8
	mov dx,bx
	mov XMSAddress,dx

	IF DEMO EQ 1

	mov ax,3d00h		       ;open file containing example
	mov dx,offset Filename	       ;picture
	int 21h
	jnc @f
	;file not found
	mov dx,offset NoFileMsg      ;file not found
	mov ah,09h
	int 21h
	;unlock XMS block
	mov dx,XMSHandle
	mov ah,0dh
	call dword ptr HandlerOffset
	;de-allocate XMS block
	mov dx,XMSHandle
	mov ah,0ah
	call dword ptr HandlerOffset
	jmp BackToDos

@@:
	mov FileHandle,ax
	mov LoadCount,64	       ;64 32k block max (2M file)
LoadLoop:
	mov ah,3fh		       ;read 32k from file
	mov bx,FileHandle
	mov cx,32768
	mov dx,offset TransferBuffer
	int 21h
	cmp ax,0		       ;bytes loaded
	je LoadDone

	mov ah,0bh		       ;mov 32k into extended memory
	mov si,offset XMSTable
	call dword ptr HandlerOffset

	add XMSOffset,32768
	dec LoadCount
	jnz LoadLoop
LoadDone:
	mov ah,3eh
	mov bx,FileHandle
	int 21h
	jmp FileLoaded

BackToDos:
	mov ah,04ch
	int 21h

FileLoaded:
	mov dx,3f2h			;turn off diskette motors
	mov al,0ch
	out dx,al
	ENDIF

	mov ah,05h		       ;local enable A20
	call dword ptr HandlerOffset

	CLI			       ;DISABLE interrupts IN RM
	;save old interrupt mask values
	in al,021h
	mov MaskValue1,al
	in al,0a1h
	mov MaskValue2,al

	mov dx,XMSAddress

	;GDT IS SET UP AS
	;
	;SEG	  SELECTor    TYPE    CONTENTS
	;0	  00	      NULL    -----
	;1	  08	      CODE    PROGRAM CODE
	;2	  10	      DATA    VARIABLE data
	;3	  18	      DATA    STACK
	;4	  20	      DATA    VIDEO MEMORY
	;5	  28	      data    static data
	;6	  30	      DATA    printer buffer
	;7->	  38->	      DATA    BUFFER MEMORY
	;
	;
	;DURING EXECUTION THE SEGMENT REGISTERS HOLD THESE SELECTORS
	;CS=08	DS=10  SS=18  ES=20  FS=28  GS=38-2468
	;ES MUST BE RETURNED TO 20 (VIDEO MEMORY) AFTER ANY ALTERATION

	mov BP,GDTS		       ;SET UP GLOBAL DESCRIPTor TABLE
	mov DS,BP		       ;USING THE SAME CODE, DATA AND
	mov BP,FSEG		       ;stack addresses and sizes
	mov FS,BP		       ;of the real mode segments
	mov CX,38h
	mov SI,offset DESCRP
	xor di,di
@@:
	mov AL,FS:[SI]
	mov [DI],AL
	inc SI
	inc DI
	LOOP @B

	mov BP,IDTS		       ;CLEAR interrupt TABLE
	mov FS,BP
	mov CX,180H
	mov AL,00H
	xor si,si
@@:
	mov FS:[SI],AL
	inc SI
	LOOP @B


	mov BX,08H		       ;STACK SEGMENTS
	mov AX,0ffffh
	mov [BX],AX		       ;LIMIT OF CODE SEGMENT
	mov AX,CS		       ;24 BIT ABSOLUTE addRESS IS
	mov CL,AH		       ;CSEG * 16
	shl AX,04H
	shr CL,04H
	mov [BX+2],AX
	mov [BX+4],CL

	mov BX,010H		       ;POINT TO DATA SEGMENT
	mov AX,(offset DSFIN-offset DSBEG)
	mov [BX],AX		       ;LIMIT
	mov AX,DSEG
	mov CL,AH
	shl AX,04H
	shr CL,04H
	mov [BX+2],AX
	mov [BX+4],CL		       ;24 BIT addRESS (DSEG * 16)

	mov BX,028H		       ;POINT TO STATIC DATA SEGMENT
	mov AX,(offset FSFIN-offset FSBEG)
	mov [BX],AX		       ;LIMIT
	mov AX,FSEG
	mov CL,AH
	shl AX,04H
	shr CL,04H
	mov [BX+2],AX
	mov [BX+4],CL		       ;24 BIT addRESS (DSEG * 16)

	mov BX,030H		       ;POINT TO printer buffer segment
	mov AX,PSEG
	mov CL,AH
	shl AX,04H
	shr CL,04H
	mov [BX+2],AX
	mov [BX+4],CL		       ;24 BIT addRESS (PSEG * 16)

	mov BX,018H		       ;POINT TO STACK SEGMENT
				       ;LIMIT IS PREDETERMINED
	mov AX,SS		       ;IN INITIAL GDT
	mov CL,AH
	shl AX,04H
	shr CL,04H
	mov [BX+2],AX
	mov [BX+4],CL		       ;START addRESS

	;dx hold XMS address
	mov bp,DSEG		       ;set to DSEG to get BufferSize
	mov ds,bp
	mov CX,BufferSize	       ;BufferSize 4K DATA SEGMENTS
	mov BP,GDTS
	mov DS,BP
	mov BP,FSEG
	mov FS,BP

	mov BX,038H		       ;SET UP SCAN MEMORY DESCRIPTORS
SCNDES:
	mov WORD PTR [BX],0fffH
	mov byte PTR [BX+2],00H
	mov [BX+3],DX		       ;limit
	mov byte PTR [BX+5],093H
	mov WORD PTR [BX+6],0000H
	add DX,010H
	add BX,08H
	LOOP SCNDES		       ;FINISHED


	;the first 8259(02xh) vectors start at 20h ie irq0=20h=idt(100h)
	;the second 8259(0axh) vectors start at 28h ie irq8=28h=idt(140h)
	;IDT IS SET UP AS
	;
	;interrupt NUMBER   IDT OFFSET	  IRQ no.   vector
	;00		    00		  sw00	    dzint (devide fault)
	;01		    08		  sw01	    DebugInt (debug trap)
	;0d		    68		  sw13	    pint (protection error)
	;20		    100 	  0	    TINT (TIMEOUT)
	;21		    108 	  1	    kint (keyboard)
	;22		    110 	  2	    cascaded 8259 #2
	;23		    118		  3	    Com24Int (nav interrupt)
	;24		    120		  4	    Com13Int (MOUSE)
	;25		    128		  5	    UINT (UART DATA READY)
	;28		    140 	  8	    rint (real time clock)

	mov BP,IDTS		       ;SET UP interrupt TABLE
	mov DS,BP


	mov BX,0H		       ;DESCRIPTor AT 0
	mov [BX],offset dzint	       ;POINT TO CS:dzint
	mov WORD PTR [BX+2],08H
	mov byte PTR [BX+4],00H
	mov byte PTR [BX+5],86H        ;STANDARD interrupt GATE

	mov BX,08H		       ;DESCRIPTor AT 8
	mov [BX],offset DebugInt       ;POINT TO CS:DebugInt
	mov WORD PTR [BX+2],08H
	mov byte PTR [BX+4],00H
	mov byte PTR [BX+5],86H        ;STANDARD interrupt GATE

	mov BX,068H		       ;DESCRIPTor For prot error
	mov [BX],offset pINT	       ;POINT TO CS:pint
	mov WORD PTR [BX+2],08H
	mov byte PTR [BX+4],00H
	mov byte PTR [BX+5],86H        ;STANDARD interrupt GATE

	mov BX,0128H		       ;DESCRIPTor For UART
	mov [BX],offset uint	       ;POINT TO CS:UINT
	mov WORD PTR [BX+2],08H
	mov byte PTR [BX+4],00H
	mov byte PTR [BX+5],86H        ;STANDARD interrupt GATE

	mov BX,0100H		       ;DESCRIPTor For TIMER
	mov [BX],offset TINT	       ;POINT TO CS:TINT
	mov WORD PTR [BX+2],08H
	mov byte PTR [BX+4],00H
	mov byte PTR [BX+5],86H        ;STANDARD interrupt GATE

	mov BX,0108H		       ;DESCRIPTor For keyboard
	mov [BX],offset kint	       ;POINT TO CS:kint
	mov WORD PTR [BX+2],08H
	mov byte PTR [BX+4],00H
	mov byte PTR [BX+5],86H        ;STANDARD interrupt GATE

	mov BX,0120H		       ;DESCRIPTor For mouse (com1)
	mov [BX],offset Com13Int	;POINT TO CS:Com13Int
	mov WORD PTR [BX+2],08H
	mov byte PTR [BX+4],00H
	mov byte PTR [BX+5],86H        ;STANDARD interrupt GATE

	mov BX,0118H		       ;DESCRIPTor For nav interrupt (com2)
	mov [BX],offset Com24Int       ;POINT TO CS:Com24Int
	mov WORD PTR [BX+2],08H
	mov byte PTR [BX+4],00H
	mov byte PTR [BX+5],86H	       ;STANDARD interrupt GATE

	mov BX,0140H		       ;DESCRIPTor For IRQ8
	mov [BX],offset RTCInt	       ;POINT TO CS:rint
	mov WORD PTR [BX+2],08H
	mov byte PTR [BX+4],00H
	mov byte PTR [BX+5],86H	       ;STANDARD interrupt GATE

	mov BX,0160H		       ;DESCRIPTor For IRQ12
	mov [BX],offset PS2MInt	       ;POINT TO CS:PS2MInt
	mov WORD PTR [BX+2],08H
	mov byte PTR [BX+4],00H
	mov byte PTR [BX+5],86H	       ;STANDARD interrupt GATE

	mov AL,012H		       ;SET VGA MODE 12H
	mov AH,00H		       ;640x480 16 COLOUR
	INT 010H
	mov AL,05H		       ;SET WRITE MODE 2
	mov AH,02H		       ;READ MODE 0
	call SETGCR
	mov BP,0A000H
	mov ES,BP		       ;VIDEO SEGMENT
	xor di,di
	mov CX,38400
	mov AL,0fh
	rep stosb
	call SetCol		       ;INITIALIZE colour registers

	mov BP,DSEG		       ;SET UP TABLES TO LOAD DESCRIPTOR
	mov DS,BP		       ;TABLE REGISTERS GDTR and IDTR

	mov BX,offset DTABLE	       ;SET UP For LGDT
	mov AX,(offset GSFIN-offset GSBEG)
	mov [BX],AX		       ;LIMIT (2054 8-byte ENTRIES)
	mov AX,GDTS
	mov CL,AH
	shl AX,04H
	shr CL,04H
	mov [BX+2],AX
	mov [BX+4],CL		       ;ABSOLUTE addRESS IS GDTS * 16

	mov BX,offset ITABLE	       ;SET UP For LIDT

	mov AX,(offset ISFIN-offset ISBEG)
	mov [BX],AX		       ;LIMIT (32 8-byte ENTRIES)
	mov AX,IDTS
	mov CL,AH
	shl AX,04H
	shr CL,04H
	mov [BX+2],AX
	mov [BX+4],CL		       ;ABSOLUTE addRESS IS IDTS * 16

	;set up the interrupt controllers for protected
	;mode operation ie. avoid vectors reserved for processor use (0-31)
	mov al,11h		       ;ICW1
	out 020h,al
	out 0a0h,al

	mov al,020h		       ;ICW2 (vectors)
	out 021h,al
	mov al,28h
	out 0a1h,al

	mov al,04h		       ;ICW3
	out 021h,al
	mov al,02h
	out 0a1h,al

	mov al,01h		       ;ICW4
	out 021h,al
	out 0a1h,al

	mov al,0ffh		       ;Mask register
	out 021h,al
	mov al,0eeh
	out 0a1h,al

	;now load descriptor table registers
	mov BX,offset DTABLE
	LGDT DescriptorTable PTR [BX]	       ;LOAD GDT REGISTER
	mov BX,offset ITABLE
	LIDT DescriptorTable PTR [BX]	       ;LOAD IDT REGISTER
	mov eax,01H
	mov cr0,eax		       ;PREPARE TO SWITCH TO PROTECTED MODE

	byte 0EAH		       ;JUMP TO PROTECTED MODE
	WORD offset VIRTMD	       ;(JMP 0008:VIRTMD) HAS TO
	WORD 0008H		       ;BE DONE WITH BYTE/WORD (0EAH=JMP)
VIRTMD:


	;THE PROCESSor IS NOW RUNNING IN PROTECTED
	;VIRTUAL addRESS MODE
	mov BP,010H
	mov DS,BP		       ;POINT DS and SS TO DESCRIPTORS
	mov BP,018H		       ;'DATAS' and 'STAKS'
	mov SS,BP
	mov BP,020H		       ;POINT ES AT VIDEO
	mov ES,BP
	mov BP,028H		       ;POINT FS AT STATS
	mov FS,BP

	IF DOS			       ;interrupts
	mov AL,DOSINTMASK		;UART(5) MOUSE(4) keyboard(1)  nav(3)
	ELSE			       ;cascade (2)
	mov al,REPINTMASK		       ;mouse (4) keyboard (1)
	ENDIF
	out 021H,AL

	call InitializeValues	       ;SET UP variables
	call SetupMouse		       ;set up mouse on com1
	call DetectPulley
	jc @f
	mov PulleyInstalled,1
	mov WasAPulley,1
@@:
	call SetupPulley		;set up pulley on com3
	mov ax,378h
	mov LPTAddress,ax	       ;get address of printer port
	call ResetPrinter

	mov al,5		       ;get printer type, baud rate and
	out 70h,al		       ;mouse speed from byte 5 of CMOS ram
	nop			       ;al=50*BaudRate+10*MouseRate+
	nop			       ;PrinterNumber
	in al,71h
	mov ah,0		       ;get BaudRate by dividing by 50
	mov bl,50
	div bl			       ;al=BaudRate
	inc al			       ;adjust 0-4 to 1-5
	call SetUartBaud	       ;ah=10*MouseRate+PrinterNumber
	mov al,ah
	aam			       ;ah=MouseRate, al=PrinterNumber
	mov MouseRate,ah
	call SelectPrinter	       ;printer in lower nibble

	IF HIPOWER
	mov al,0
	mov dx,210h
	out dx,al
	ENDIF

	call SetScheme
	call PrintStatusBar	       ;BRING UP STATUS LINE

	mov AX,010h		       ;initial mouse position
	mov MouseXCoord,ax	       ;store it
	mov MouseYCoord,ax	       ;store it
	mov MouseMoved,1
	IFE DEMO
	call sreset		       ;SCSI RESET
	call ClearMainBuffer	       ;CLEAR MAIN BUFFER
	call ResetUart		       ;RESET 6402
	ENDIF

	IF DEMO EQ 2
	call ClearMainBuffer	       ;CLEAR MAIN BUFFER
	ENDIF

	call CalcSquares	       ;SQUARES For MAP MODE
	call CalcLogarithms	       ;logarithms
	call SetPal		       ;initialize palette

	IF DEMO EQ 1
	mov al,64
	sub al,LoadCount	       ;work out how long the file was
	mov ah,0
	shl ax,5
	mov cline,ax		       ;display loaded record
	ENDIF

	IFE DEMO or DISKLESS
	call rsense		       ;SCSI REQUEST SENSE
	ENDIF

	IF DOS or REPLAY
	cmp DriveError,1
	je ExitToDos
	ENDIF

	IFE DEMO or DISKLESS
	call prmere		       ;SCSI DISABLE EJECT BUTTON
	ENDIF
	cld			       ;clear direction flag
	call SetupRTC
	STI			       ;ALL SYSTEMS GO!
	;THE MAIN LOOP STARTS HERE
	mov al,0ch		       ;kick off RTC interrupts
	out 70h,al
	in al,71h
	call RemoveArrow
	mov InitRedraw,1	       ;redraw screen straight away
	;*test
	;mov al,8
	;mov CoaxPower,al
	;or al,2
	;mov dx,211h
	;out dx,al
	;*test
MAIN1:
	test SnapshotPending,0c0h      ;if a snapshot (.BMP or DJ) is pending
	jne KeyDone		       ;freeze the keyboard
	call GETKEY		       ;SCAN KEYPAD
	jnc KeyDone


	call KeyboardBleep	       ;KEYBOARD BLEEP
	mov al,KeyCode
	cmp al,80h		       ;^F12 quits
	je ExitToDos
	mov ah,LeftButton	       ;if either of the mouse buttons are
	or ah,RightButton	       ;down, give 'Invalid key' error
	jne @f
	JMP KeyPress		       ;service it
@@:
	mov si,offset ErrorMsg3        ;'invalid key'
	call Rebuke


KeyDone:			       ;KEY PRESS FUNCTIONS RETURN HERE
	test InitRedraw,1	       ;IS A REDRAW NEEDED?
	je @F			       ;IF SO start it
	call StartRedraw	       ;TO SET UP REDRAW
@@:
	;now see if a redraw is progress
	test InitRedraw,2
	je RDLDone		       ;jump if not
	call PRLINE		       ;returns carry set if redraw finished
	jnc RDLDone		       ;jump if success
	;the redraw has finished

	and InitRedraw,0fdh	       ;SIGNAL REDRAW FINISHED
	test BannerPrinted,1
	jne @f
	;if this is the end of the first redraw, print version message
	call PrintBanner	       ;print C-MAX message
	mov BannerPrinted,1
@@:
	cmp FreezeMode,0
	je NonFMode
	;does the freeze window need redrawing or has it just been done?
	cmp dx,8960
	je @f
	;freeze window has been done
	call DoubleLine 	       ;if freeze was on, restore divider
	jmp NonFMode
@@:
	;start a redraw of the freeze window
	test WindowFlag,0ffh	       ;not if a window is up
	jne NonFMode
	mov NewCurZoom,2
	mov RedrawMapLine,64
	mov ax,ScreenLineMap[128]
	mov RLINE,AX
	mov InitRedraw,02H
	call SCRNAD
	add BX,9200
	call StartR1
	jmp RDLDone
NonFMode:
	;all areas have been redrawn
	and NewCurZoom,1
	mov LookBackScrl,0
	mov HideMouse,0
	call PrintArrow		       ;draw arrow
	mov al,SnapshotPending	       ;screen or printer snapshot waiting?
	test al,0c0h
	je RDLDone		       ;skip if not
	test al,80h		       ;screen or printer
	jne @f
	call DoBitmap		       ;screen save/export
	jmp SnapsAllDone
@@:
	call ComenceHPDump	       ;printer dump
SnapsAllDone:
	mov SnapshotPending,0
RDLDone:
	mov AX,DLine
	cmp AX,CLINE
	je @F			       ;IS A NEW LINE READY?
	call PDLINE		       ;IF SO PRINT THE DONE LINE
	jmp RDLDone		       ;back for more
@@:
	;see if the sonar has been turned on
	cmp SonarIsOn,1 	       ;if the sonar data is coming in
	jne Main20
	cmp SonarWasOn,1	       ;check if it was last time round
	je Main20
	mov SonarWasOn,1

	call StatusMode
Main20:
	cmp ClockTick,1
	jne Main15
	mov ClockTick,0
	mov AL,00H
	out 070H,AL
	IN AL,071H		       ;get seconds from byte 0
	mov SECONDS,AL		       ;update seconds

	mov AL,02H		       ;get minutes from byte 2
	out 070H,AL
	IN AL,071H
	cmp al,Minutes		       ;are the different
	je @F
	mov MINUTES,AL		       ;if the time has changed (every minute)
	or FeatureFlag,04H	       ;signal 'time box'
@@:
	mov AL,04H
	out 070H,AL
	IN AL,071H
	mov HOURS,AL		       ;update hours
	;now do things that happen once a second
	call StatusTime		       ;PRINT THE NEW TIME
	test Seconds,0fh
	jnz @f
	mov AllowNewGLL,1
@@:
	;if a pulley is connected, read it
	IF DOS
	test PulleyInstalled,1
	je NoPulley
	call ReadPulley
	setnc PulleyInstalled
	jc @f
	cmp ax,10000
	je NoPulley
	cmp ax,CableScope
	je NoPulley
	mov CableScope,ax
	call StatusScope
	jmp NoPulley
@@:
	mov PulleyInstalled,0
	mov si,offset ErrorMsg36
	call Rebuke
	call StatusScope
NoPulley:
	ENDIF
	mov al,RightButton
	or al,LeftButton
	jne @f
	;xor ArrowColour,0fh	       ;toggle arrow colours
	mov MouseMoved,1
@@:
	cmp AutoStart,0 	       ;auto start recording if the
	je @f			       ;fish was running when the software
	dec AutoStart		       ;first runs
	cmp AutoStart,0
	jne @f
	cmp SonarIsOn,1
	je StartAutoRec
@@:

	test seconds,0fh	       ;re-examine printer lag every 10 secs
	jne NoPLag
	test PFlag,1		       ;only sound if printer is on
	je NoPLag
	mov ax,cline
	mov bx,oline
	cmp ax,bx
	jae @f
	add ax,BufferSize
@@:
	sub ax,bx		       ;if oline is 100 or more behind cline
	cmp ax,100
	jbe NoPLag
	or AlarmFlag,10h	       ;then trigger alarm

NoPLag:
	test NewValues,1	       ;if the battery voltage
	je @f			       ;has changed, print it
	call StatusBattery
	and NewValues,0feh
@@:
	test NewValues,2	       ;if the altitude
	je @f			       ;has changed, print it
	call StatusAltitude	       ;update the status line
	and NewValues,0fdh
@@:
	test NewValues,4	       ;if the course
	je @f			       ;has changed, print it
	call StatusCourse	       ;update the status line
	and NewValues,0fbh
@@:
	test NewValues,8	       ;if the relative heading
	je @f			       ;has changed, print it
	call StatusAngle	       ;update the status line
	and NewValues,0f7h
@@:
	test NewValues,10h	       ;if the depth sounding
	je @f			       ;has changed, print it
	call StatusSounding	       ;update the status line
	and NewValues,0efh
@@:
	test NewValues,20h	       ;if the speed
	je @f			       ;has changed, print it
	call StatusSpeed	       ;update the status line
	and NewValues,0dfh
@@:
	;flash the 'Live' in the status area
	cmp SonarIsOn,1 	       ;is data being recieved
	jne @f
	cmp StorageMode,0		       ;record mode on?
	jne @f
	call StatusMode 	       ;update status bar
@@:
	;now see if the sonar has switched off
	mov AL,SonarIsOn	       ;is data being recieved
	cmp al,1		       ;if so, jump ahead
	je SonarIsGoing
	;if it is off, see if it was on before
	cmp SonarWasOn,1
	jne @f
	;the sonar has switched off so activate alarm
	call StatusMode 	       ;update status bar
	or AlarmFlag,1		       ;bit 0=stop alarm
	mov SonarWasOn,0
	mov RangeNumber,10	       ;invalid range
	mov LineLength,0
	mov BatteryVoltage,0
	mov Altitude,0
	;no response from fish, turn power off
	;mov CoaxPower,0
	;mov dx,211h
	;mov al,2
	;out dx,al
	jmp @f
SonarIsGoing:
	mov SonarIsOn,0
@@:
Main15:
	;now do everything on the periodic (1/16 second) tick
	cmp PeriodTick,1
	jne NoPeriodTick
	mov PeriodTick,0
	;now sound the alarms if needed
	mov al,PTickCount
	mov ah,AlarmFlag	       ;masking for altitude alarm
	test AlarmControl,ah	       ;bit 0=stop 1=alt. 2=disk 3=leak 4=lag
	je NoAlarms
	mov si,offset AlarmTones
@@:
	inc si
	shr ah,1
	jnc @b
	mov ah,fs:[si]
	mov cl,PTickCount
	shr cl,1
	and cl,07h
	inc cl
	shr ah,cl
	mov al,3
	jc @f
NoAlarms:
	mov al,0
@@:
	out 061h,al
	;print alarm messages
	mov al,AlarmFlag
	test al,0ffh		       ;are any alarms on?
	je ClearAlarmMsg
	test PTickCount,7
	jne NoPeriodTick
	;now print messages
	mov di,offset AlarmMsg2        ;'Low altitude'
	cmp Altitude,0
	jne @f
	mov di,offset AlarmMsg2a	;'No altitude'
@@:
	test al,2
	jne @f
	test PTickCount,8	       ;are seconds even
	jne PAlarmMsg1
	mov di,offset QToCancelMsg
	jmp @f
PAlarmMsg1:
	mov di,offset AlarmMsg1        ;'Fish stopped'
	test al,1
	jne @f
	mov di,offset AlarmMsg3        ;'Low disk'
	test al,4
	jne @f
	mov di,offset AlarmMsg4        ;'Leak detected'
	test al,8
	jne @f
	mov di,offset AlarmMsg5        ;'Printer lag'
@@:
	call petext
	mov AlarmHistory,1	       ;alarm message printed
	jmp NoPeriodTick

ClearAlarmMsg:
	;clear the message only if an alarm has been on
	test AlarmHistory,1
	je NoPeriodTick
	mov di,offset tspace
	call petext
	mov AlarmHistory,0

NoPeriodTick:
	test LinkError,1
	je NoLinkError
	mov LinkError,0
	mov di,offset ErrorMsg19
	call PEText
	mov ecx,50000
@@:
	loopd @b
	mov di,offset TSpace
	call PEText

	;call PrintErrorMsg
NoLinkError:
	cmp StorageMode,1		       ;is play mode on?
	jne NoNewSpeed
	mov al,LSpeed		       ;is there a new speed?
	cmp al,Speed
	je NoNewSpeed
	mov Speed,al
	call StatusSpeed
NoNewSpeed:

	test TelemetryReady,1	       ;is the Telemetry data complete?
	je MAIN8		       ;jump if not
	mov TelemetryReady,0	       ;reset flag
	mov si,(offset TelemetryData+13) ;
	mov al,[si]
	cmp byte ptr [si],80h
	jmp @f
	or AlarmFlag,08h	       ;trigger leak alarm
@@:
	dec si
	mov al,[si]
	mov BatteryVoltage,AL	       ;store it
	cmp SonarIsOn,1
	jne @f
	or NewValues,1
@@:
	;extract telemetry
	mov BX,offset TelemetryData	 ;the altitude is coded in the Telemetry
	mov CL,4		       ;data as below
	mov AL,0
DecAltLoop:
	mov AH,[BX+3]		       ;bit 6 of mon. byte#	altitude bit
	cmp ah,112
	jae @f
	cmp ah,96
	jbe @f
	jmp Main10		       ;ignore this reading
@@:
	cmp ah,112
	setnc ah

	or AL,AH		       ;3			0
	Ror AL,1		       ;2			1
	mov AH,[BX+2]		       ;7			2
	cmp ah,112
	jae @f
	cmp ah,96
	jbe @f
	jmp Main10		       ;ignore this reading
@@:
	cmp ah,112
	setnc ah

	or AL,AH		       ;10			5
	Ror AL,1		       ;15			6
	add BX,4		       ;14			7
	dec CL
	jnz DecAltLoop

	;altitude now in al
	NOT AL			       ;invert it

	cmp AL,Altitude		       ;has it changed?
	je MAIN8
	mov Altitude,AL 	       ;if so, store it and
	or NewValues,2		       ;flag new altitude
MAIN8:
	mov al,15		       ;check if the altitude is
	;less than 2.5m
	cmp Altitude,al		       ;if it is, sound the alarm
	Ja @f
	;Altitude is low so sound alarm
	cmp SonarWasOn,1	       ;don't sound if sonar is off
	jne @f
	or AlarmFlag,2		       ;bit 1=altitude alarm
	jmp Main10
@@:
	and AlarmFlag,0fdh
MAIN10:
	test HBoxReady,01H	       ;IS IT TIME For A Altitude MARK?
	je MAIN12		       ;IF NOT, SKIP
	or FeatureFlag,080H	       ;SIGNAL Altitude MARK
	mov HBoxReady,0
	;THE DIRECTORY IS ALSO UPDATED EVERY 256 LINES IN CASE
	;OF POWER FAILURE
	test StorageMode,2
	je MAIN12
	mov AL,CURREC		       ;GET RECORD NUMBER
	mov AH,00H
	shl AX,5		       ;X32
	mov SI,offset DIRSEC
	add SI,AX		       ;offset IN SECTOR
	mov al,Hours		       ;update the time
	mov [si+18],al		       ;and the
	mov al,Minutes
	mov [si+19],al
	mov EAX,CurrentCluster	       ;CURRENT SECTOR
	mov [SI+24],EAX 	       ;UDATE DIR
	call WDIRS		       ;SAVE IT

MAIN12:
	test NavDataReady,1	       ;is new nav data complete?
	je main75		       ;if not, jump

	;allow ony one nav message every 10 seconds
	mov di,offset NavDataBuffer
	call ValidNavString
	jc NotGLLMsg			;jump if string is not nav
	test AllowNewGLL,1		;10 seconds up
	je NavDataStored		;ignore this nav string
	;process as normal
	mov AllowNewGLL,0
	jmp @f				;give position messages priority
NotGLLMsg:
	test FeatureFlag,08h
	jne SkipNavComp 		;dont overwrite existing data
@@:
	;the data in 'NavDataBuffer' is compressed into 'CompNavString'
	xor bx,bx		       ;source pointer in bx
	mov di,bx		       ;desination pointer in di
CompMain:
	mov al,NavDataBuffer[bx]       ;get character
	cmp al,0ffh		       ;string terminator?
	je CompTerm
	cmp bx,60		       ;end of string?
	jae CompTerm
	call CompressChar	       ;is it 0-9 , .
	jnc CompressAscii	       ;jump if not
	;find out number of consecutive digits
	mov dl,0
	push bx 			;save source
@@:
	inc dl				;digit count
	cmp dl,0fh			;14 digits max
	je @f
	mov al,NavDataBuffer[bx]	;get character
	inc bx
	call CompressChar		;is it 0-9 , .
	jc @b				;if so, loop back
@@:
	pop bx				;restore pointer
	mov al,dl			;load count
	dec al
	;store count in nibble [di]
Compress3:
	call StoreNibble
	jc CompTerm
@@:
	dec dl
	jz CompMain			;digit string has been compressed
	;now store the string
	mov al,NavDataBuffer[bx]	;convert to nibble
	call CompressChar
	call StoreNibble
	jc CompTerm
	inc bx
	jmp @b


CompressAscii:
	mov al,0			;0=ascii string follows
	call StoreNibble
	jc CompTerm
CompAsc1:
	mov ax,word ptr NavDataBuffer[bx]	;get two characters
	xchg al,ah
	cmp al,0ffh			;end of string
	je @f
	call CompressChar		;or digit
	jnc CompAsc2
@@:
	or ah,80h			;last in string
CompAsc2:
	mov al,ah			;store character, low nibble first
	and al,0fh
	call StoreNibble
	jc CompTerm
	mov al,ah
	shr al,4
	call StoreNibble
	jc CompTerm
	inc bx
	test ah,80h			;last character?
	je CompAsc1
	jmp CompMain

CompTerm:
	mov al,0fh
	call StoreNibble
	;done
	or FeatureFlag,08h	       ;if so signal 'nav data'

SkipNavComp:
	;now scan the nav message for data
	;the speed, course and headingare contained in the NMEA0183 messages
	mov SI,(offset NavDataBuffer+3)
	;'$GPVTG,xxx,T,x.x,M,x.x,N,x.x,K'
	cmp dword ptr [si],',GTV'	;is it a VTG message?
	je DecodeNavVTG
	;'$GPHDT,xxx,T'
	cmp dword ptr [si],',TDH'	;is it a HDT message?
	je DecodeNavHDT
	cmp dword ptr [si],',CTU'	;is it a UTC message?
	je DecodeNavUTC
	cmp word ptr [si],'BD'		;is it a DBx message?
	je DecodeNavDBx
	;scan the message for the character '='
FSScanLoop:
	inc si
	cmp si,(offset NavDataBuffer+63)
	je NavDataStored		;end of buffer?
	mov al,[si]
	cmp al,13			;end of message?
	je NavDataStored
	cmp al,'='
	jne FSScanLoop
	inc si
	call GetDecimal
	;in m/s, divide by two
	shl dx,1
	mov ax,dx
	shl dx,2
	add dx,ax
	add dl,cl
	shr dx,1
	cmp dx,50			;max speed is 4.0 m/s
	ja NoVTGSpeed
	mov Speed,dl
	or NewValues,20h
	jmp NavDataStored

DecodeNavVTG:
	mov cl,5
	call FindParameter		;speed is after 5 commas
	jc NoVTGSpeed
	call GetDecimal
	;in m/s, divide by two
	shl dx,1
	mov ax,dx
	shl dx,2
	add dx,ax
	add dl,cl
	shr dx,1
	cmp dx,40			;max speed is 4.0 m/s
	ja NoVTGSpeed
	mov Speed,dl
	or NewValues,20h
NoVTGSpeed:
	;see if there is a course
	mov si,offset NavDataBuffer
	mov cl,1
	call FindParameter
	jc NotVTGMsg		       ;is there a value?
	call GetDecimal
	jc NotVTGMsg		       ;is it a number?
	cmp dx,359
	ja NotVTGMsg		       ;is it a valid course?
	cmp dx,NavCourse
	je NotVTGMsg		       ;is it new?
	mov NavCourse,dx
	or NewValues,4	       ;signal new course
NotVTGMsg:
	jmp NavDataStored

DecodeNavDBx:
	;the depth sounding is contained in the NMEA0183 message
	;'$xxDBx,,,xxx.x,M
	mov cl,3
	call FindParameter
	jc NotDBXMsg
	call GetDecimal
	jc NotDBXMsg
	shl dx,1
	mov ax,dx
	shl dx,2
	add dx,ax
	add dl,cl
	mov Sounding,dx
	or NewValues,10h
NotDBXMsg:
	jmp NavDataStored

DecodeNavHDT:
	;the heading is contained in the NMEA0183 message
	;'$GPHDT,xxx,T'
	mov cl,1
	call FindParameter
	jc NotHDTMsg
	call GetDecimal
	jc NotHDTMsg		       ;is it a number?
	cmp dx,359
	ja NotHDTMsg		       ;is it a valid heading?
	sub dx,NavCourse	       ;get relative heading
	;now adjust it so it is -180 < Rel Hdg < +180
	cmp dx,180
	jl @f
	sub dx,360
	jmp RelHead1
@@:
	cmp dx,-180
	jg RelHead1
	add dx,360
RelHead1:
	cmp dx,45
	jle @f
	mov dx,45
	jmp RelHead2
@@:
	cmp dx,-45
	jge RelHead2
	mov dx,-45
RelHead2:
	cmp dl,NavAngle
	je NotHDTMsg
	mov navAngle,dl
	or NewValues,8
NotHDTMsg:
	jmp NavDataStored

DecodeNavUTC:
	;this gets the time (Time, Universal Coordinated)
	;from the message '$XXUTC,hhmmss'
	mov cl,1
	call FindParameter
	mov ch,4
@@:
	mov ax,[si]
	sub ax,'00'
	shl al,4
	or ah,al
	mov al,ch
	out 70h,al
	mov al,ah
	out 71h,al
	add si,2
	sub ch,2
	jnc @b

NavDataStored:
	mov NavDataReady,0	       ;reset handshake
	mov dx,02fch		       ;set RTS and DTR active
	mov al,0bh
	out dx,al

main75:
	test NewRangeFlag,01	       ;IF THERE IS A RANGE CHANGE,
	je @F			       ;PRINT IT
	mov TargetRange,0
	mov NewRangeFlag,00H	       ;reset range change flag
	call StatusRange	       ;in the status line
	;now open up a range change window
	;this displays the new range in large figures
	;on the screen for a short time
	mov al,RangeNumber
	and al,0fh
	cmp al,10		       ;is the range valid?
	je @f			       ;if not, don't print big
	cmp StorageMode,01h		       ;is it in play mode?
	je @f			       ;if so, don't print big
	call bigrng
@@:

	test StorageMode,02H		       ;IS RECORD MODE ON?
	je MAIN52		       ;IF NOT, JUMP
	mov DX,RELINE		       ;IF A 16 LINEs are READY, RECORD
	mov BX,CLINE		       ;them
	sub bx,dx
	jns @f
	add bx,BufferSize
@@:
	cmp BX,16
	Jbe MAIN52
	call Write16		       ;WRITE THE LINEs
	jnc WriteSuc
	;a disc error has occoured
	mov DX,0211H		       ;RESETS SCSI BUS
	mov AL,00H
	out DX,AL
	NOP
	NOP
	NOP
	NOP
	IF NOOFBITS EQ 6
	mov al,6		       ;78bit
	ELSE
	mov al,2
	ENDIF
	out DX,AL
	call rsense
	mov StorageMode,0
	call StatusMode
	mov si,offset ErrorMsg16       ;'disk error'
	call Rebuke
	jmp main52

WriteSuc:
	mov BX,RELINE
	add bx,16
	cmp TroubleSelector,0ffffh
	je @f
	inc bx
@@:
	and bx,BufferLimit
	mov RELINE,BX
	;now check remaining disk space
	mov EAX,CurrentCluster	       ;CAPACITY IS CurrentCluster/32 FIRST
	shr EAX,3		       ;DIV BY 32
	mov BL,39
	cmp MediaType,0 	       ;128MB
	je @f
	mov bl,71
	cmp MediaType,1 	       ;230MB
	je @f
	mov bl,198		       ;640
@@:
	DIV BL
	cmp al,99		       ;>99%
	jbe @f
	mov al,99		       ;if so, set to 99 used (0 free)
@@:
	mov AH,99
	SUB AH,AL
	mov AL,AH
	cmp STCAP,AL
	je MAIN52
	;if it has changed, update the status bar
	mov STCAP,AL
	test DiskAlarm,1
	jne @f
	and AlarmFlag,0fbh
	cmp al,3
	jae @f
	or AlarmFlag,04h	       ;sound the alarm if it is less than 3%
	mov DiskAlarm,1 	       ;if alarm is canceled, dont restart
@@:
	call StatusSpace
MAIN52:
	test StorageMode,01H		       ;IS PLAY MODE ACTIVE?
	je MAIN53		       ;IF NOT JUMP
	mov al,Pausef		       ;pause if either mouse button
	or al,LeftButton	       ;is down, or if pause is on
	or al,RightButton
	;or al,FreezeMode
	jne MAIN53
	test InitRedraw,02H	       ;SUSPEND IF A REDRAW IS IN
	jne MAIN53		       ;PRORESS

	mov EAX,CurrentCluster	       ;get current cluster
	cmp StopCluster,EAX	       ;is it at the end of the record?
	JA NOSEQU		       ;if not, jump ahead

	;the current record has finished
	;depending on the sequence and
	;repeat settings the next one might be played

	test SequenceFlag,3	       ;is 'Sequence' or 'Repeat' on?
	je PLYOFF		       ;if not, stop Play mode

	cmp SequenceCount,0	       ;if count value is already zero, leave
	je @f			       ;it ie play indefinatly
	dec SequenceCount	       ;otherwise decrement sequence counter
	je PLYOFF		       ;if this is at zero, stop Play mode
@@:
	;if 'Sequence' is on the next record is to be played
	;if 'Repeat' is on the same record is to be played
	mov FWDINC,1		       ;turn off cue mode
	call LDIRS		       ;RELOAD DIRECTORY
	mov bl,CURPLY		       ;GET CURRENT RECORD NUMBER
	test SequenceFlag,2	       ;is 'Repeat' on?
	jne @f			       ;if so, don't inc. play number
	inc bl			       ;NEXT ONE
	mov CURPLY,bl		       ;STORE IT
@@:
	mov bh,00H		       ;GET offset IN DIRECTORY
	shl bx,5
	lea SI,DIRSEC[bx]	       ;GET addRESS OF ENTRY in si
	mov EAX,[SI+24]		       ;get STOP CLUSTER
	cmp byte PTR [SI],00H	       ;are there no more records
	jne @F			       ;if there are, jump ahead
	;when the end of the disk is reached and wraparound is set
	;the records are played from the begining again
	mov si,offset dirsec
	mov EAX,[SI+24] 	       ;get new stop cluster
	mov CURPLY,00H		       ;reset current play number

@@:
	;now start another record playing
	mov StopCluster,EAX	       ;STORE stop cluster
	mov EAX,[SI+20]		       ;GET START CLUSTER
	mov CurrentCluster,EAX	       ;STORE IT
	mov StartCluster,eax
	call CLRBOX		       ;clear the annotation box
	call WriteFilename
	;now carry on with Play processing

NOSEQU:
	;first see if the screen is ready for more data
	mov DX,CLINE		       ;compare the current print line
	cmp DX,DLINE		       ;with the last loaded line
	jne MAIN53		       ;if they are different, finish
	call ReadS		       ;READ A LINE IN
	mov EAX,CurrentCluster
	mov GS:[0f9cH],EAX	       ;TAG LINE WITH CLUSTER NUMBER
	;now see if any values such as speed and layback have changed
	mov ax,gs:[0f88h]	       ;get layback
	cmp ax,NavLayback	       ;new?
	je @f
	mov NavLayback,ax	       ;store it if so
	call StatusLayback
@@:
	mov ax,gs:[0ffeh]
	cmp ax,Sounding
	je @f
	mov Sounding,ax
	call StatusSounding
@@:
	mov AL,GS:[0f83H]	       ;GET RANGE
	cmp AL,RangeNumber	       ;new range?
	je @F			       ;if not, jump
	mov RangeNumber,AL	       ;store new range
	mov NewRangeFlag,01H	       ;set flag range change
@@:
	mov al,gs:[0f87h]	       ;get relative angle
	cmp al,NavAngle 	       ;new?
	je @f
	mov NavAngle,al 	       ;store it if so
	or NewValues,8
@@:
	mov al,gs:[0f84h]	       ;get altitude
	cmp al,Altitude 	       ;new?
	je @f
	mov Altitude,al 	       ;store it if so
	or NewValues,2	       ;flag 'new altitude'
@@:
	mov ax,gs:[0f85h]	       ;get heading
	cmp ax,NavCourse	       ;new?
	je @f
	mov NavCourse,ax	       ;store it if so
	call StatusCourse
@@:
	test FORWAD,01H 	       ;IS IT IN cue MODE
	je NORMPY		       ;IF NOT, JUMP ahead
	mov AX,CLINE		       ;is so, process line for Cue
	shl AX,3		       ;first get segment of
	add AX,038H		       ;current line
	mov GS,AX
	mov BL,GS:[0f8dH]	       ;get the flags in bl
	cmp FWDINC,01H		       ;is the line step 1 or 4?
	je GOSLOW		       ;if it is 1, jump ahead
	;should be locked on to every fourth line
	test BL,020H		       ;has a feature been missed?
	jne SKIPBK		       ;if so, skip back
	test BL,010H		       ;is the 'fourth line' flag set?
	je SKIPBK		       ;should be, but if not, skip back
	add CurrentCluster,4	       ;otherwise advance cluster by 4
	JMP GOLINE		       ;and print the line

GOSLOW:
	;the clusters are being searched consecutively
	;for a 'fourth line' flag

	test BL,010H		       ;'fourth line' flag set?
	je @F			       ;if not, jump
	mov FWDINC,4		       ;if so, sync has been found so
@@:				       ;set step rate to 4
	movzx eax,FWDINC	       ;increase the cluster by the
	add CurrentCluster,EAX
	test BL,087H
	je MAIN53		       ;if there is nothing to print, abort
	JMP GOLINE		       ;otherwise print the line


SKIPBK:
	;come here if a feature skipped flag is found
	;this means that a feature is present in the last 3 lines

	mov FWDINC,01H		       ;set the step rate to 1
	SUB CurrentCluster,3	       ;back up the cluster number 3 places
	JMP MAIN53		       ;and carry on



NORMPY:
	;normal Play mode comes here

	inc CurrentCluster	       ;increment cluster
GOLINE:
	mov BX,CLINE		       ;and current line
	inc BX			       ;checking for wraparound
	and bx,BufferLimit
	mov CLINE,BX
MAIN53:
	test MouseMoved,1	       ;has any mouse action occured?
	je main59		       ;if not, jump all mouse related code
	;a mouse action has happened, now it is decoded
	;first the left button
	test LeftButton,1	       ;is the left button down
	je main61		       ;if not, jump ahead

	test WindowFlag,0ffh	       ;are any windows up?
	jne main61
	test ManualAltitude,1		;manual altitude mode?
	je CentreZoom
	call AlterAltitude
	jc Main61
	mov InitRedraw,1
	jmp Main61

	;if not, start a cursor centred zoom
CentreZoom:
	;is this the first time?
	cmp NewCurZoom,1
	je @f
	mov al,FreezeMode		;save the status of freeze mode
	mov SavedFreeze,al
@@:
	mov NewCurZoom,1
	;see if right button has just been pressed
	test RightButton,1		;if right button is not down
	je @f				;jump
	test JustPressedR,1
	jne NoContAdj
	mov JustPressedR,1		;right button has just been pressed
	call AlterContrast
	jmp NoContAdj
@@:
	test JustPressedR,1
	mov JustPressedR,0
	jne main59

NoContAdj:
	test HideMouse,1
	jne @f
	call RemoveArrow
@@:
	call CursorZoom 	       ;trigger the zoom redraw
	mov JustPressedL,1
	jmp main59

main61:
	cmp JustPressedL,1
	jne main60
	;come here if the left button has just been released
	call RemoveArrow
	mov ContrastNumber,0
	mov ContrastMul,0
	mov JustPressedL,0		;restore normal screen by starting
	mov al,SavedFreeze
	mov FreezeMode,al		;a redraw but if freeze mode was
	test al,1			;was freeze on?
	je @f
	mov NewCurZoom,2
	mov RedrawMapLine,64
	mov ax,ScreenLineMap[128]
	mov RLINE,AX
	mov InitRedraw,02H
	call SCRNAD
	add BX,9200
	call StartR1
	jmp Main60
@@:
	;start a full redraw
	mov InitRedraw,1
	mov NewCurZoom,0
main60:
	;now the right button is decoded
	;test LeftButton,1	       ;if the left button is down, the
	;jne main59		       ;right button is disabled
	test RightButton,1	       ;is the right button down?
	je MoveCrossHair	       ;if not, jump ahead
	test JustPressedR,1	       ;has the button been pressed
	je CalcShadow1		       ;if so, jump
	;if not, calculate and display height
	call GetDistance
	;for the measurement to be valid, ax must be the same sign and
	;greater value than ShadowStart
	cmp cl,SStartSign
	jne NoShadow
	cmp ax,ShadowStart
	jb NoShadow
	;ax holds D+S
	push ax 		       ;push D+S
	sub ax,ShadowStart		;ax=S
	movzx bx,byte ptr gs:[0f84h]	;get altitude in bx
	shl bx,1
	;now convert alt. from 160mm units to 100mm units (x1.6)
	mov dx,0
	shl bx,2		       ;x4
	mov cx,5
	xchg ax,bx
	div cx			       ;/5
	xchg ax,bx
	mul bx			       ;dx:ax=SA
	pop bx			       ;get D+S
	cmp bx,00
	je DivZero
	div bx			       ;get H=SA/(D+S)	 in ax
	cmp ax,0		       ;is height 0?
	;je NoShadow
	mov si,offset InfoMessage
	mov bl,0
@@:				       ;first find hundreds
	cmp ax,100
	jb @f
	sub ax,100
	inc bl
	jmp @b
@@:
	cmp bl,0
	je @f			       ;suppress leading zero
	add bl,'0'
	mov [si],bl
	inc si
@@:
	aam
	add ax,3030h
	mov [si],ah
	mov byte ptr [si+1],'.'
	mov [si+2],al
	mov word ptr [si+3],0206dh     ;'m '
	mov dword ptr [si+5],'hgih'
	mov byte ptr [si+9],0ffh
NoShadEnt:
	call pitext
DivZero:
	mov AnnotationUsed,1
	jmp main59

NoShadow:
	mov si,offset InfoMessage
	mov dword ptr [si],'norW'
	mov dword ptr [si+4],'aw g'
	mov byte ptr [si+8],'y'
	mov byte ptr [si+9],0ffh
	jmp NoShadEnt

CalcShadow1:
	;the button has just been pressed
	;the distance between the two cursors is calculated
	;and displayed
	call GetDistance	       ;get distance to arrow in ax
	mov ShadowStart,ax	       ;store it for shadow measurement
	mov SStartSign,cl
	;now get the cursor seperation
	mov ax,MouseYCoord
	sub ax,CursorYCoord
	cwde			       ;sign extend to eax
	mov ebx,eax		       ;y distance in ebx
	mov ax,MouseXCoord	       ;x distance in eax
	sub ax,CursorXCoord
	cwde			       ;sign extend to eax
	imul eax,eax		       ;eax=eax^2
	imul ebx,ebx		       ;ebx=ebx^2
	add eax,ebx		       ;eax^2+ebx^2
	;now find the square root of eax
	call SquareRoot
	;value in ax
	;now scale the value according to the range
	mov dx,ax		       ;save value
	mov bx,MouseYCoord	       ;get y co-ordinate
	shl bx,1
	mov ax,ScreenLineMap[bx]
	;ax now holds the buffer line that the arrow is on
	cmp ax,BufferLimit
	jbe @f
	mov si,offset ErrorMsg6 	;'wrong record'
	call Rebuke
	jmp KeyDone

@@:
	shl AX,3		       ;calculate segment
	add AX,038H
	mov gs,ax
	mov cl,gs:[0f83h]	       ;get range from line
	mov ch,cl		       ;save in ch for later
	and cl,0fh		       ;mask out frequency bit

	mov bx,75		       ;150m
	cmp cl,3
	je @f

	mov bx,62
	cmp cl,2		       ;125m
	je @f

	mov bx,50
	cmp cl,1		       ;100m
	je @f

	mov bx,25		       ;50m
	cmp cl,0
	je @f

	mov bx,100
	cmp cl,4		       ;200m
	je @f

	mov bx,150
	cmp cl,5		       ;300m
	je @f

	mov bx,200		       ;400m
	cmp cl,6
	je @f

	mov bx,37		       ;75m
	cmp cl,7
	je @f

@@:
	;range dependent multiplier in bx
	mov ax,dx
	test ScreenZoom,1	       ;if there is no zoom on
	je @f			       ;jump ahead
	shr ax,1		       ;otherwise divide by 2
	test ScreenZoom,4	       ;if zoom is x 2, jump ahead
	je @F			       ;otherwise divide by 2 again
	shr ax,1
@@:				       ;add in the pan position*40
	;distance in 640ths in ax
	;convert to metres
	mul bx
	shr ax,4

	;ax now in metres/10
	mov si,offset InfoMessage
	mov bl,0
@@:				       ;first find hundreds
	cmp ax,1000
	jb @f
	sub ax,1000
	inc bl
	jmp @b
@@:
	mov cl,bl		       ;save hundreds
	cmp bl,0
	je @f			       ;suppress leading zero
	add bl,'0'
	mov [si],bl
	inc si
@@:				       ;then find tens
	mov bl,0
@@:
	cmp ax,100
	jb @f
	sub ax,100
	inc bl
	jmp @b
@@:
	or cl,bl
	je @f			       ;suppress leading zero but not
	add bl,'0'		       ;if hundreds<>0
	mov [si],bl
	inc si
@@:
	mov bl,0
@@:
	cmp ax,10
	jb @f
	sub ax,10
	inc bl
	jmp @b
@@:
	add bl,'0'
	mov [si],bl
	mov byte ptr [si+1],'.'
	add al,'0'
	mov [si+2],al
	mov word ptr [si+3],0ff6dh     ;'m',0ffh
	;now move the cross hair to the new position
	cmp ScreenGeometry,2		       ;map mode?
	je @f
	;remind user about geometry if not in map mode
	mov si,offset GeoMessage
	call Rebuke
@@:
	call pitext
	mov AnCur,0
	mov ax,MouseXCoord
	mov CursorXCoord,ax
	mov ax,MouseYCoord
	mov CursorYCoord,ax
	mov MouseMoved,00h		       ;cancel mouse moved flag
	mov JustPressedR,1
	jmp main59

MoveCrossHair:
	;this is called when the right button is released
	;ie mouse is moved, right button not down and
	;JustPressed is set
	;first check if JustPressed is set
	cmp JustPressedR,1
	jne main59		       ;if not, abort
	mov JustPressedR,0

main59:
	test MouseMoved,01H	       ;has mouse interrupt been called?
	je MAIN54		       ;if not, skip
	;MOUSE HAS MOVED
	test ManualAltitude,1
	je @f
	mov ax,MouseYCoord
	add ax,5
	mov CursorYCoord,ax
	mov ax,MouseXCoord
	mov dx,632
	sub dx,ax
	mov CursorXCoord,dx
@@:
	test HideMouse,1	       ;is mouse visible
	jne @f
	call RemoveArrow	       ;erase arrow
@@:
	call SCRNAD		       ;GET ORIGIN OF SCREEN
	add BX,4240
	mov si,bx		       ;save it
	;now work out addresses 'arrow' and 'CursorAddress'
	mov ax,MouseXCoord
	shr ax,3		       ;screen address is int(MouseXCoord/8)+
				       ;80*MouseYCoord+4240
	add BX,AX
	mov ax,MouseYCoord	       ;get y co-ordinate
	shl AX,4		       ;*16
	add BX,AX		       ;add it to total
	shl AX,2		       ;*64
	add BX,AX		       ;add it
	mov ARROW,BX		       ;store address in 'arrow'
	mov ax,CursorXCoord
	shr ax,3		       ;screen address is int(CursorXCoord/8)+
				       ;80*MouseYCoord+4240
	add si,AX
	mov ax,CursorYCoord	       ;get y co-ordinate
	sub ax,5
	shl AX,4		       ;*16
	add si,AX		       ;add it to total
	shl AX,2		       ;*64
	add si,AX		       ;add it
	mov CursorAddress,si	       ;store address in 'arrow'
	test HideMouse,1	       ;is mouse visible
	jne @f
	call PrintArrow		       ;draw arrow
@@:
	mov MouseMoved,00H	       ;reset 'mouse moved' flag


MAIN54:
	;check if the printing is up to date
	cmp PFLAG,00H		       ;is the printer on?
	je NPRINT		       ;if not, jump forward
	cmp SonarIsOn,1 	       ;live data?
	jne @f
@@:
	mov AX,OLINE		       ;has the printer caught up
	cmp AX,CLine		       ;up with the new data
	je @F			       ;if so, jump forward
	call StorePrintLine	       ;store this line in the buffer
@@:
	;now see if there is a line to be sent to the printer
PAGAIN:
	mov AL,OHEAD		       ;first see is otail>ohead
	cmp AL,OTAIL		       ;if so, add 32 to ohead value
	jae @f
	add al,32
@@:
	sub al,otail		       ;if the gap between ohead and
	cmp al,20		       ;otail>20 then print the line
	jbe nprint
	call [PrinterDriver]	       ;call the selected driver
	JMP PAGAIN
NPRINT:
	;if freeze mode is on, check for lookback scrolling
	cmp FreezeMode,1		;only in freeze mode
	jne Main65
	test WindowFlag,03fh		;not if any menus etc are up
	jne Main65
	test InitRedraw,02H		;IS A REDRAW IN PROGRESS?
	jne Main65
	;make sure that new data doesnt catch up
	mov bx,ScreenLineMap[850]	;scan line at bottom of window
	mov ax,ScreenLineMap[128]	;scan line at top of window
	cmp ax,bx			;make sure top>bottom
	ja @f
	;if the top<bottom ie top has wrapped round, the condition
	;to see if 'CLine' is in the window is:
	;CLine>bottom or CLine<top
	cmp Cline,bx			;if CLine>bottom
	ja Main66			;OR
	cmp Cline,ax			;CLine<top
	jb Main66			;scroll forward
	jmp Main67
@@:
	;if the top>bottom ie top has not wrapped round, the condition
	;to see if 'CLine' is in the window is:
	;CLine>bottom and CLine<top
	cmp Cline,bx
	jbe Main67
	cmp Cline,ax
	jb Main66
Main67:
	cmp MouseYCoord,422		;mouse at bottom of screen
	jae LBScrollBack
	cmp MouseYCoord,5		;mouse at top of screen
	jbe LBScrollForward

	cmp UpDownCount,0
	je Main65
	test UpDownCount,80h
	je @f
	;value is negative
	inc UpdownCount
	jmp LBScrollForward
@@:
	dec UpDownCount
	jmp LBScrollBack

Main66:
	;come here if the lookback is forced forward
	mov AntiBounce,1
	cmp MouseYCoord,422
	jb @f
	dec MouseYCoord
@@:
	jmp LBForceForward

LBScrollBack:
	cmp AntiBounce,1
	je Main65
	;scroll back 16 screen lines
	call RemoveArrow
	mov HideMouse,1
	call Scrnad
	mov cx,27840			;scroll freeze window up 16 lines
	mov di,9200			;top of freeze window
	add di,bx
	lea si,[di+1280]		;scroll 16 lines at a time
	mov ax,0105H		       ;set write mode 1
	call SETGCR
	rep movsb es:[di],es:[si]
	mov ax,0205H		       ;SET WRITE MODE 2
	call SETGCR
	;now scroll Screenmap up 16 lines
	mov si,offset ScreenLineMap[128]
	mov cx,348		       ;move (479-115)-16=348 lines
@@:
	mov ax,[si+32]
	mov [si],ax
	add si,2
	loop @b

	mov ax,500h			;adjust location of features
	sub TAddr,ax
	sub HAddr,ax
	sub VAddr,ax
	sub NAddr,ax

	mov si,offset RedrawAnBuffer
	mov cl,8
@@:
	sub word ptr [si],500h
	add si,10h
	dec cl
	jnz @b

	;now redraw the bottom 16 lines
	mov ax,ScreenLineMap[852]	;get bottom of screen
	mov RLine,ax			;redraw from that buffer line
	mov RedrawMapLine,411		;position is ScreenLineMap
	mov LookBackScrl,1		;signal to PRLINE scroll up
	call SCRNAD
	add bx,37040			;screen address
	call StartR2			;prepare redraw parameters
@@:
	call prline
	jnc @b
	and NewCurZoom,1
	and InitRedraw,0FDH	       ;SIGNAL REDRAW FINISHED
	mov LookBackScrl,0
	call PrintArrow		       ;draw arrow
	mov HideMouse,0
	jmp main65


LBScrollForward:
	;scroll forward 16 screen lines
	mov AntiBounce,0
LBForceForward:
	mov ax,cline
	sub ax,ScreenLineMap[232]
	jns @f
	add ax,BufferSize
@@:
	cmp ax,125
	ja @f
	inc MouseYCoord
	jmp Main65
@@:
	mov HideMouse,1
	call RemoveArrow
	call Scrnad
	mov LookBackScrl,2		;signal lookback down
	mov cx,27840			;scroll freeze window down 16 lines
	mov di,38399			;(27840 bytes)
	add di,bx			;di=bottom of freeze window
	lea si,[di-1280]		;scroll 16 lines at a time
	mov ax,0105H		       ;set write mode 1
	call SETGCR
	std
	rep movsb es:[di],es:[si]
	cld
	mov ax,0205H		       ;SET WRITE MODE 2
	call SETGCR
	;now scroll Screenmap down 16 lines
	mov si,offset ScreenLineMap[854]
	mov cx,348		       ;move (479-115)-16=348 lines
@@:
	mov ax,[si-32]
	mov [si],ax
	sub si,2
	loop @b
	;now draw top 16 lines
	mov RedrawLine,1	       ;SIGNAL REDRAW LINE (sort of)
	call ScrnAd		       ;get address of 16th line of freeze
	add bx,10560		       ;window
	mov RedrawAddress,bx
	mov RedrawMapLine,79
	mov ax,ScreenLineMap[128]
	mov RLine,ax
LBSF1:
	mov ax,RLine
	call PLine
	;now display features
	mov bx,RedrawAddress
	call LookBEnter
	;fill in ScreenLineMap
	cmp ScrollDrop,0	       ;if no lines were printed
	je LBSF2		       ;dont alter ScreenLineMap
	movzx cx,ScrollDrop	       ;number of lines printed
	mov ax,rline		       ;add redraw screen line to
	mov bx,RedrawMapLine	       ;get index number
	sub RedrawMapLine,cx
	shl bx,1		       ;word pointer
@@:
	mov ScreenLineMap[bx],ax       ;fill screen line map
	sub bx,2
	loop @b
LBSF2:

	mov ax,RLine
	inc ax
	and ax,BufferLimit
	mov RLine,ax

	call SCRNAD		       ;first see if the redraw is done
	mov ax,RedrawAddress	       ;redraw address in ax, screentop in bx
	sub ax,bx		       ;get difference in ax
	mov dx,09200		       ;9200=draw up to top of window
	cmp ax,dx		       ;if the redraw has got to the bottom
	jae LBSF1		       ;of the screen, stop it
	mov LookBackScrl,0	       ;end lookback
	call DoubleLine
	mov HideMouse,0
	call PrintArrow
	and InitRedraw,0FDH	       ;SIGNAL REDRAW FINISHED
Main65:
EndOfMain:
	JMP MAIN1		       ;back to the main loop

LookDownFill:
	mov LookBackScrl,0
	call KeyboardBleep
	jmp Main65


StartRedraw: ;this starts the redraw
	call RemoveArrow
	mov HideMouse,1 	       ;hide mouse until redraw is complete
	mov RedrawMapLine,0
	mov AX,DLINE
	SUB AX,1
	and ax,BufferLimit		;wrap round
	mov RLINE,AX		       ;FIRST REDRAW LINE (DLINE-1)

	mov InitRedraw,02H	       ;SIGNAL REDRAW STARTED
	call SCRNAD
	add BX,4160
StartR1:
	mov BHEAD,0
	mov BTAIL,0
	;clear feature redraw flags
	mov al,0
	mov TNavFlag,al
	mov VFlag,al
	mov HFlag,al
	mov TFlag,al
StartR2:
	mov RedrawAddress,BX	       ;FIRST addRESS (below status bar)
	mov al,ScreenZoom
	mov RedrawZoom,al	       ;copy zoom and pan settings
	mov al,ScreenPan
	shl al,2
	mov RedrawPan,al
	RET

CursorZoom:
	;this brings up a X4 zoom window of the area around the arrow
	mov bx,MouseYCoord	       ;get arrow Y co-ordinate
	sub bx,50		       ;offset
	jns @f			       ;make sure it is not off
	xor bx,bx		       ;the top of the screen
@@:
	shl bx,1
	mov ax,ScreenLineMap[bx]
	and ax,BufferLimit
	mov RLINE,AX		       ;FIRST REDRAW LINE

	mov InitRedraw,02H	       ;SIGNAL REDRAW STARTED
	call SCRNAD
	add BX,9200
	mov RedrawAddress,BX		       ;FIRST addRESS (window top)

	mov BHEAD,0
	mov BTAIL,0
	call DoubleLine 	       ;print a dividing line
	mov RedrawMapLine,86
	mov al,5		       ;X4 zoom
	mov RedrawZoom,al
	mov ax,MouseXCoord	       ;get x mouse distance
	add ax,5		       ;add offset
	mov bl,10		       ;split screen into 64ths
	div bl
	cmp ScreenZoom,0	       ;is there any zoom?
	je NoCurZoom
	shr al,1
	test ScreenZoom,4	       ;X2 or X4?
	je @f
	shr al,1
@@:
	mov ah,ScreenPan
	shl ah,2
	add al,ah
NoCurZoom:
	sub al,8
	jns @f
	mov al,0		       ;butt against left hand side
@@:
	cmp al,48
	jbe @f			       ;and right hand side
	mov al,48
@@:
	mov RedrawPan,al
	mov FreezeMode,3
	mov HideMouse,1
	RET


KeyPress: ;ENTERS HERE WITH CLOSE CODE IN AL



ANCHAR:
	cmp AL,0FH		       ;delete? if so jump to andel
	je ANDEL		       ;
	mov bx,offset ktran
	xlatb fs:ktran		       ;translate key to ascii
	cmp AL,'Q'		       ;'Q'?  (cancel a window)
	jne NormalQ
	test AlarmFlag,0fdh
	je @f
	mov al,0
	mov AlarmFlag,al	       ;kill alarms
	out 061h,al
	jmp KeyDone
@@:
	test WindowFlag,2	       ;if directory is active, turn it
	Jne diroff		       ;off
	test WindowFlag,4	       ;if help is active, turn it off
	jne HLPFIN
	test WindowFlag,1	       ;if function is on, turn it off
	jne FunctionCancel
	test WindowFlag,70h	       ;if printer or nav menu is on
	jne prmcel		       ;kill it
NormalQ:
	cmp AL,0FFH		       ;if ascii code is 0ffh, the key
	je FunctionKeys		       ;is a function key

	test WindowFlag,010H	       ;if printer menu is
	jne prmkey		       ;on, jump to printer select
	cmp AL,'A'		       ;if the character is a
	jb nvfkey		       ;letter a-z
	test WindowFlag,01H	       ;and function menu is
	jne FUNCKY		       ;on, jump to FUNCKY
	test WindowFlag,020h	       ;if nav menu is on
	jne navkey		       ;jump to navkey
nvfkey:

	cmp AnnotationUsed,01H	       ;has the annotation been used?
	jne @F			       ;if so, clear the box first
	push AX
	call CLRBOX
	pop AX
@@:
	test SETTMF,01H 	       ;IS IT IN TIME SET MODE?
	je @F			       ;IF NOT, JUMP
	cmp AL,'9'		       ;IF CODE>9?
	JA KeyDone		       ;IF SO, ABORT
	cmp ANCUR,5
	jae KeyDone
@@:
	mov BL,ANCUR		       ;anno. cursor in bl
	cmp BL,10		       ;10 characters max.
	jne @F
	mov si,offset ErrorMsg1        ;'10 chars only'
	call Rebuke		       ;Rebuke if full
	jmp KeyDone		       ;IN BUFFER FULL, abort
@@:
	mov BH,00H
	add BX,offset ANBUFF	       ;calculate pointer in bx
	mov [BX],AL		       ;add character to annotation string
	mov byte ptr [bx+1],0ffh       ;update terminator
	call patext		       ;print annotation text
	inc ANCUR		       ;ADVANCE POINTER
	test SETTMF,01H 	       ;if in time set mode
	je @F			       ;and cursor
	cmp ANCUR,2		       ;is in position 2
	jne @F
	mov bx,offset anbuff	       ;then add a colon and
	mov byte ptr [bx+2],':'	       ;increment cursor
	mov ANCUR,3
@@:
	jmp KeyDone

ANDEL:	;THIS DELETES A CHARACTER FROM THE ANNOTATION BUFFER
	mov AnnotationUsed,00H	       ;clear annotation used flag
	mov al,ANCUR		       ;is box clear already?
	and al,al		       ;if so, abort
	je KeyDone
	mov AH,0
	dec AL
	mov SI,offset ANBUFF
	add SI,AX
	mov byte PTR [SI],0FFH
	mov ANCUR,AL
	call patext		       ;print text
	jmp KeyDone

	;THE FUNCTION KEYS ARE (^=SHIFT)

FunctionKeys: ;THIS call THE APPROPRIATE FUNCTION KEY ROUTINE
	mov al,KeyCode

	cmp al,23h
	je func11		       ;PAN LEFT
	cmp al,1fh
	je func12		       ;PAN RIGHT
	cmp al,018h
	je CalcNavFix		       ;calc position
	cmp al,01ah
	je func10		       ;ZOOM IN
	cmp al,01bh
	je funs10		       ;ZOOM OUT
	cmp al,020h
	je func5		       ;geometry

	IF DEMO
	cmp al,019h
	je DemoOnly		       ;event mark
	cmp al,01ch
	je SetLayback		       ;set layback
	ELSEIFE REPLAY
	cmp al,01ch
	je SetLayback		       ;set layback
	cmp al,019h
	je funs8		       ;event mark
	ELSE
	cmp al,01ch
	je SetLogFile		       ;set logfile
	ENDIF


	cmp al,034h
	je helpm		       ;info pages
	cmp al,01eh
	je func9		       ;freeze mode
	cmp al,021h
	je HideShowKey		       ;hide/show all screen features
	cmp al,02ch
	je PNavMenu		       ;bring up nav menu
	cmp al,028h
	je FuncPrintMenu	       ;bring up print menu

	cmp al,038h
	IF DOS
	je srecol		       ;start record mode
	ELSEIF REPLAY
	je LogPosition
	ENDIF

	cmp al,01dh		       ;annotate the screen
	je FixAnnotation
	cmp al,22h		       ;invert the palette
	je ivideo
	cmp al,030h		       ;display function menu
	je fmenu

	IF DEMO
	cmp al,03ch
	je DemoOnly
	cmp al,03dh
	je DemoOnly
	cmp al,03eh		       ;edit the screen to disk
	je DemoOnly
	cmp al,03fh		       ;turn cue mode on
	je DemoOnly
	cmp al,00h		       ;PAUSE PLAYBACK
	je DemoOnly
	cmp al,01h		       ;start play mode
	je DemoOnly
	cmp al,038h
	je DemoOnly		       ;start record mode
	ELSE
	cmp al,03ch
	je sstop
	cmp al,03dh
	je DisplayDirectory	       ;DISPLAY DIRECTORY
	cmp al,03eh		       ;edit the screen to disk
	je copy
	cmp al,03fh		       ;turn cue mode on
	je cueon
	cmp al,00h		       ;PAUSE PLAYBACK
	je pause
	cmp al,01h		       ;play record
	je splay
	ENDIF

	mov si,offset ErrorMsg3        ;'invalid key'
	call Rebuke
	jmp KeyDone

	IF DEMO
DemoOnly:
	mov si,offset DemoMsg
	call Rebuke
	jmp KeyDone
	ENDIF

Registertest:
	mov eax,CurrentCluster
	mov ErrorEAX,eax
	call PrintRegValue
	inc RegisterNumber
	mov AnnotationUsed,1
	cmp RegisterNumber,9
	jb @f
	mov RegisterNumber,0
@@:
	jmp KeyDone

FUNC10: ;ZOOM OUT
	;first see if test mode is on
	cmp dword ptr anbuff,'TSTR'
	jne NoRegtest
	cmp AnnotationUsed,1
	je @f
	mov RegisterNumber,0
@@:
	jmp Registertest
NoRegtest:
	cmp dword ptr anbuff,'TSTK'
	je FuncKeytest
	IF DOS
	cmp dword ptr anbuff,'TDPU'
	je WriteSoftUpdate
	ENDIF
	mov AL,ScreenZoom
	cmp AL,00H		       ;IS ZOOM out MAX?
	je ZMOUTE
	cmp AL,01H		       ;X2?
	je ZMOUT1
	SUB ScreenPan,2
	cmp ScreenPan,00H
	JGE @F
	mov AL,ScreenPan
	mov FOURP,AL
	mov ScreenPan,00H
@@:
	cmp ScreenPan,08H
	JLE @F
	mov AL,ScreenPan
	SUB AL,08H
	mov FOURP,AL
	mov ScreenPan,08H
@@:
	mov ScreenZoom,01H
	JMP ZOOMOD
ZMOUT1:
	mov ScreenZoom,00H
ZOOMOD:
	call StatusZoomPan		       ;and ZOOM MODE INDICATOR
	mov InitRedraw,1		       ;REDRAW NEEDED
	jmp KeyDone

AlterContrast:
	mov al,ContrastNumber
	mov bx,180h
	cmp al,0
	je @f
	mov bx,140h
	cmp al,1
	je @f
	mov bx,100h
	cmp al,2
	je @f
	;mov bx,280h
	;cmp al,3
	;je @f
	mov bx,000h
@@:
	mov ContrastMul,bh
	mov ContrastOff,bl
	mov al,ContrastNumber
	inc al
	cmp al,4
	jne @f
	mov al,0
@@:
	mov ContrastNumber,al
	ret


ZMOUTE: ;ZOOM out ERROR
	mov si,offset ErrorMsg4	       ;'zoom limit'
	call Rebuke
	jmp KeyDone

FUNS10: ;ZOOM IN
	mov AL,ScreenZoom
	cmp AL,05H		       ;IS ZOOM IN MAX?
	je ZMinE
	cmp AL,01H		       ;X2?
	je @F
	mov ScreenZoom,01H
	JMP ZOOMID
@@:
	mov ScreenZoom,05H
	add ScreenPan,2
	mov AL,FOURP
	add ScreenPan,AL
	mov FOURP,00H
ZOOMID:
	call StatusZoomPan		       ;and ZOOM MODE INDICATOR
	mov InitRedraw,1		       ;REDRAW NEEDED
	jmp KeyDone


zmine:	;zoom in error
	mov si,offset ErrorMsg4        ;'zoom limit'
	call Rebuke
	jmp KeyDone

FUNC11: ;THIS PANS THE WINDOW LEFT
	test ManualAltitude,1
	je @f
	mov si,offset ErrorMsg15	;wrong mode
	call Rebuke
	jmp KeyDone
@@:
	cmp ScreenZoom,00H
	jne @F
	mov si,offset ErrorMsg5        ;pan limit
	call Rebuke
	jmp KeyDone
@@:
	mov AL,ScreenPan
	SUB AL,1		       ;IF PAN=0 DO NOTHING
	JNC @F
	mov si,offset ErrorMsg5        ;pan limit
	call Rebuke
	jmp KeyDone
@@:
	mov ScreenPan,AL
	call StatusZoomPan		       ;REPRINT PAN/ZOOM WINDOW
	mov InitRedraw,1
	jmp KeyDone

FUNC12: ;THIS PANS THE WINDOW RIGHT
	test ManualAltitude,1
	je @f
	mov si,offset ErrorMsg15	;wrong mode
	call Rebuke
	jmp KeyDone
@@:
	cmp ScreenZoom,00H
	jne @F
	mov si,offset ErrorMsg5        ;pan limit
	call Rebuke
	jmp KeyDone
@@:
	mov AL,ScreenPan
	add AL,4
	mov AH,ScreenZoom		       ;IF ZOOM IS X2, PAN MUST BE<=8
	and AH,04H		       ;IF ZOOM IS X4, PAN MUST BE<=12
	SUB AL,AH
	cmp AL,12
	jb @F
	mov si,offset ErrorMsg5        ;pan limit
	call Rebuke
	jmp KeyDone
@@:
	inc ScreenPan
	call StatusZoomPan
	mov InitRedraw,1
	jmp KeyDone

FUNS2:	;THIS CLEARS THE ANNOTATION BOX
	call CLRBOX
	jmp KeyDone

CLRBOX:
	mov ANCUR,0		       ;RESET THE CURSOR
	mov SI,offset ANBUFF	       ;FILL THE BUFFER WITH 0FFH
	mov CL,12
FNS21:
	mov byte PTR [SI],0FFH
	inc SI
	dec CL
	jnz FNS21
	call patext
	mov AnnotationUsed,00H
	RET

HideShowKey:
	xor HideShowFlag,1
	mov InitRedraw,1
	jmp KeyDone

	IF REPLAY

SetLogFile:
	;this sets a new filename for the log file
	cmp AnCur,0			;any text?
	jne @f
	mov si,offset ErrorMsg17	;'no text'
	call Rebuke
	jmp KeyDone
@@:
	mov AnnotationUsed,1
	;now copy the string into LogFileName
	mov si,offset AnBuff
	mov di,offset LogFileName
	mov cl,8			 ;8 chars max
@@:
	mov al,[si]
	cmp al,'0'
	jb @f
	cmp al,'Z'
	ja @f
	mov [di],al
	inc si
	inc di
	dec cl
	jnz @b
@@:
	cmp cl,8
	jne @f
	mov si,offset ErrorMsg30	;'Bad filename'
	call Rebuke
	jmp KeyDone
@@:
	mov dword ptr [di],'GOL.'
	mov byte ptr [di+4],0

	jmp KeyDone

	ENDIF

SetLayback:
	;set towfish layback in metres
	mov si,offset anbuff
	call GetDecimal
	mov AnnotationUsed,1
	jc LaybackError
	cmp dx,9999
	ja LaybackError
	mov NavLayback,dx
	call StatusLayback
	jmp KeyDone

LaybackError:
	mov si,offset ErrorMsg12
	call Rebuke
	jmp KeyDone

FUNC9:	;THIS TOGGLES FREEZE MODE
	test FreezeMode,1
	je NFRD
	;IF FREEZE WAS ON, COME HERE
	;DONT TURN FREEZE OF IF HELP, DIRECTORY OR
	;FUNCTION MENU IS ON
	cmp WindowFlag,00H
	je @F
	mov si,offset ErrorMsg3
	call Rebuke
	jmp KeyDone
@@:

	mov FreezeMode,00H	       ;TURN FREEZE OFF
	mov InitRedraw,01H		       ;SIGNAL REDRAW
	jmp KeyDone

NFRD:	;IF FREEZE WAS OFF, COME HERE
	mov UpDownCount,0
	mov FreezeMode,1	       ;SETTING FREEZE FLAG AS THIS FLAG
	;clear feature redraw flags
	mov al,0
	mov TNavFlag,al
	mov VFlag,al
	mov HFlag,al
	mov TFlag,al
	;now draw a dividing line
	call DoubleLine
	;check mouse is not going to start a lookback scroll
	mov ax,MouseYCoord
	cmp ax,4
	jne @f
	inc ax
@@:
	cmp ax,422
	jne @f
	dec ax
@@:
	jmp KeyDone

DoubleLine:
	;this draws a two pixel thick grey line to divide off
	;the freeze window
	mov dx,03ceh
	mov al,8
	out dx,al		       ;set bit mask to 11111111
	inc dx
	mov al,0ffh
	out dx,al
	call scrnad
	add bx,9040		       ;2 lines of draw 80 bytes
	mov cl,80
	mov al,07h
@@:
	mov es:[bx],al
	mov es:[bx+80],al
	inc bx
	dec cl
	jnz @b
	ret

FUNC5:	;THIS CYCLES THE GEOMETRY MODE
	test ManualAltitude,1
	je @f
	mov si,offset ErrorMsg15	;wrong mode
	call Rebuke
	jmp KeyDone
@@:
	mov AL,ScreenGeometry
	inc AL
	cmp AL,3
	jne @F
	mov AL,00H
@@:
	mov ScreenGeometry,AL
	call StatusGeometry
	mov InitRedraw,01H
	jmp KeyDone


FUNS8:	;THE SETS A EVENT MARK and GIVES IT A NUMBER
	;event marks are only accepted in Record mode'
	cmp StorageMode,02h		       ;record mode on?
	je @f
	mov si,offset ErrorMsg15	;'wrong mode'
	call Rebuke
	jmp KeyDone

@@:
	or FeatureFlag,01H	       ;SIGNAL EVENT MARK
	;if event marks are not visible, make them so and start a redraw
	test DisplayFlags,8	       ;visible?
	jne @f
	or DisplayFlags,8	       ;make it so
	mov HideShowFlag,0
	mov InitRedraw,1
@@:
	jmp KeyDone		       ;thats it

FixAnnotation:
	;this fixes the annotation text from the text window
	;to the picture at the position shown by the annotation arrow
	;it is functional is both Record and Play modes
	;first check error posibilities
	mov AnnotationUsed,01h	       ;signal annotation used
	cmp AnCur,0		       ;is there any text there?
	jz func89		       ;if not, 'no text'

	IFE DEMO
	test StorageMode,03h	       ;is Record or Play mode on?
	je func91		       ;if not, 'wrong mode'
	call VerifyForWrite	       ;check write protect
	jne func90		       ;if on, 'write protected'
	ENDIF
	test HideMouse,1
	jne @f
	call RemoveArrow	       ;erase arrow
@@:

	;now find out which buffer line is being
	;pointed to by the arrow

	mov bx,MouseYCoord		       ;get y co-ordinate
	shl bx,1
	mov ax,ScreenLineMap[bx]

	;ax now holds the buffer line on which to fix the annotation
	;the disk cluster is recorded at the end of the line
	;first check limits
	cmp ax,BufferLimit
	jbe @f
	mov si,offset ErrorMsg6 	;'wrong record'
	call Rebuke
	jmp KeyDone

@@:

	mov cx,ax		       ;save the line number in cx
@@:
	shl ax,3		       ;calculate segment
	add ax,038h
	mov bx,ax		       ;save it in bx for later
	mov gs,ax
	test byte ptr gs:[0f8dh],02h   ;is there already annotation here?
	je LineIsClear		       ;if not, jump ahead
	inc cx			       ;increase line number
	and cx,BufferLimit	       ;wrap round
	mov ax,cx		       ;copy into ax
	jmp @b

LineIsClear:
	IFE DEMO
	mov edx,gs:[0f9ch]	       ;get the cluster number from the line
	;now check if this cluster is contained in the current record
	;first is it before the first cluster?
	cmp StartCluster,edx	       ;if it is before the start, abort
	jae func88
	cmp StorageMode,02h		       ;is it in record mode?
	je @f
	cmp StopCluster,edx	       ;stop cluster only matters in
	jbe func88		       ;Play mode
@@:
	mov gs,ax		       ;load segment

	test byte ptr gs:[0f8dh],010h  ;is the line a cue line?
	jne CueLineFound	       ;if so, jump out
	add ax,8		       ;if not go to the
	cmp ax,LastSelector	       ;next line, wrapping round if
	jne @b			       ;needed
	mov ax,038h
	jmp @b			       ;and try again

CueLineFound:
	;ax now contains the segment for the nearest cue
	;line to the actual annotated line
	or byte ptr gs:[0f8dh],020h    ;set the feature skipped flag

	SUB AX,038H
	shr AX,3
	mov DX,AX		       ;get the line number in dx
	mov EAX,GS:[0f9cH]	       ;get the cluster number from the line
	;now check if this cluster is contained in the current record
	;first is it before the first cluster?
	cmp StartCluster,eax	       ;if it is before the start, abort
	ja func88
	cmp StorageMode,02h		       ;is it in record mode?
	je @f
	cmp StopCluster,eax	       ;stop cluster only matters in
	jb func88		       ;Play mode
@@:
	push CurrentCluster	       ;push the current cluster number
	mov CurrentCluster,EAX	       ;store it as the current cluster
	push bx 		       ;push segment
	push cx 		       ;push line number
	call WriteS		       ;write the altered line
	pop cx			       ;restore line number
	pop gs			       ;get the segment for annotation in gs

	ENDIF
	or byte ptr gs:[0f8dh],02h     ;SET ANNOTATION present FLAG
	;now the annotation text is copied from the
	;annotation buffer to the line (03c9h onwards)
	mov di,0f90h
	mov si,offset anbuff
	mov bl,10
@@:			       ;COPY THE TEXT FROM THE BUFFER
	lodsb
	mov gs:[di],al
	inc di
	dec bl
	jne @b
	mov byte ptr gs:[di],0ffh      ;string terminator

	;now the pan position for the annotation must be
	;calculated from the mouse

	mov ax,MouseXCoord		       ;get mouse x position (0-639)
	shr ax,2		       ;reduce to a pan position (0-159)

func84:
	test ScreenZoom,1		       ;if there is no zoom on
	je func85		       ;jump ahead
	shr al,1		       ;otherwise divide pan by 2
	test ScreenZoom,4		       ;if zoom is x 2, jump ahead
	je @f			       ;otherwise divide pan by 2 again
	shr al,1
@@:				       ;add in the pan position*10
	mov ah,ScreenPan
	shl ah,1
	add al,ah
	shl ah,2
	add al,ah
func85:
	mov gs:[0f9bh],al	       ;SET PAN POSITION
	IFE DEMO
	mov eax,gs:[0f9ch]	       ;GET CLUSTER
	mov CurrentCluster,eax
	mov dx,cx		       ;GET SCAN LINE NUMBER
	call WriteS
	pop CurrentCluster
	ENDIF
	mov bx,Arrow		       ;print the annotation on the screen
	mov si,offset anbuff
	call fixan
	test HideMouse,1
	jne @f
	call PrintArrow		       ;draw arrow
@@:
	;if annotation is not visible, make it so and start a redraw
	test DisplayFlags,1	       ;visible?
	jne @f
	or DisplayFlags,1	       ;make it so
	mov HideShowFlag,0
	mov InitRedraw,1
@@:
	jmp KeyDone		       ;finished

FUNC88:
	mov si,offset ErrorMsg6 	;'wrong record'
	call Rebuke
	jmp KeyDone

func89:
	mov si,offset ErrorMsg17       ;'no text'
	call Rebuke
	jmp KeyDone

func90:
	mov si,offset ErrorMsg2        ;'write protected'
	call Rebuke
	jmp KeyDone

func91:
	mov si,offset ErrorMsg15	;'wrong mode'
	call Rebuke
	jmp KeyDone


IVIDEO:
	Xor invpal,0ffH
	call psgrsc
	mov InitRedraw,1
	jmp KeyDone

DisplayDirectory:
	;this brings up the directory in a window
	call rsense
	call VerifyForRead		       ;CHECK disk IS IN
	jnc @f
	mov si,offset ErrorMsg7        ;'no disk'
	call Rebuke		       ;Rebuke IF NOT
	jmp KeyDone
@@:
	call LDIRS		       ;LOAD THE DIRECTORY SECTORS
	jnc @f
	mov si,offset ErrorMsg41
	call Rebuke
	jmp KeyDone
@@:

	call RemoveArrow
	test WindowFlag,2	       ;is directory already active?
	jne @f			       ;if not, kill others
	call SwapWindow
@@:
	mov WindowFlag,2	       ;directory mode on
	;call PRMERE		       ;PREVENT REMOVAL
	test DIRFLG,01H 	       ;HAVE ALL ENTRIES BEEN SHOWN
	jne DIROFF		       ;IF SO, CLEAN UP
	call ClearWindow	       ;clear window
	;FIRST FIND THE CAPACITY REMAINING
	mov si,offset DIRSEC
	mov EAX,0000H
@@:
	cmp byte PTR [SI],00H
	je @F
	mov EAX,[SI+24] 	       ;last cluster of last record
	add SI,20H
	JMP @B
@@:
	shr EAX,3		       ;DIV BY 32
	mov BL,39
	cmp MediaType,0 	       ;128MB
	je @f
	mov bl,71
	cmp MediaType,1 	       ;230MB
	je @f
	mov bl,198
@@:
	DIV BL
	cmp al,99		       ;>99%
	jbe @f
	mov al,99		       ;if so, set to 99 used (0 free)
@@:
	mov AH,99
	SUB AH,AL
	mov AL,AH
	mov STCAP,AL
	call StatusSpace	       ;print capacity
	mov FreezeMode,01H	       ;SET FREEZE MODE
	call ClearWindow	       ;CLEAR BOTTOM OF SCREEN
	call SCRNAD
	add BX,9927		       ;BX IS TOP OF WINDOW
	mov WSPointer,BX     ;store it
	call PHEADR		       ;PRINT HEADER
	mov BX,WSPointer     ;bring screen pointer 3 lines down
	add BX,4480
	mov WSPointer,BX
DIRLP2:
	movzx si,DIRNUM		       ;get number of record to be printed
	shl si,5		       ;each record is 32 bytes
	add SI,offset DIRSEC	       ;SI=START OF RECORD(DIRNUM)
	cmp byte PTR [SI],00H	       ;is the a record there?
	je NOFILE		       ;if [si]=0, there are no more files
	;a valid file has been found
	;first print the file number
	mov al,LightFuncText
	mov TextColour,al	       ;white text for numbers
	mov di,offset testmsg	       ;offset of destination string
	mov AL,DIRNUM		       ;0-63
	inc AL			       ;1-64
	mov AH,0		       ;file number in ax
	aam
	add ax,3030h		       ;ascii adjust both digits
	cmp ah,'0'		       ;IS FIRST DIGIT '0'?
	jne @F			       ;IS SO, PRINT A 8 pixel wide
	mov ah,'|'		       ;space (|)
@@:
	xchg al,ah
	mov [di],ax		       ;store both digits
	add di,2
	mov word ptr [di],0efb2h
	add di,2

	;now the name is copied to 'testmsg'
	mov CH,10		       ;TEN CHARS IN NAME
	inc SI			       ;POINT SOURCE AT NAME
	lea dx,[si+12]
@@:
	mov AL,[SI]		       ;GET CHAR
	cmp al,0ffh
	je @f
	mov [di],al
	inc SI			       ;inc SOURCE
	inc di			       ;increment string pointer
	dec CH			       ;dec COUNT
	jnz @b			       ;LOOP BACK 10 times
@@:
	mov byte ptr [di],0b5h	       ;tab character
	inc di
	;now store the date, start time and end time
	mov si,dx
	;first get the day
	mov AL,[SI]
	cmp al,0		       ;is the record normal or 'edit'
	jne NormalEntry 	       ;if normal, jump ahead
	mov dword ptr [di],'TIDE'      ;print 'EDIT' instead of date
	mov byte ptr [di+4],0ffh       ;don't put any times
	jmp DirEntryDone	       ;done

NormalEntry:
	mov CH,AL
	shr AL,4		       ;FIRST DIGIT of day
	add al,30h
	cmp al,'0'		       ;blank out leading zeros
	jne @f
	mov al,'|'
@@:
	mov [di],al
	and ch,0FH
	add ch,30h
	mov [di+1],ch		       ;second digit
	;next comes month
	mov byte ptr [di+2],'>'	       ;print space between day and month
	inc SI			       ;point to month
	mov bl,[SI]		       ;GET MONTH
	;the month is printed in a three letter abbreviation eg 'Jan'
	;it is stored in bcd format
	cmp bl,9		       ;first convert to binary fromat
	jbe @f
	sub bl,6
@@:
	dec bl
	mov bh,0
	shl bx,2		       ;dword pointer
	mov eax,dword ptr fs:MonthNames[bx]
	mov [di+3],eax
	;next comes year
	inc SI			       ;point to year
	mov AL,[SI]		       ;GET year
	mov CH,AL
	shr AL,4
	add al,30h
	mov [di+7],al		       ;store first digit
	and ch,0FH
	add ch,30h
	mov [di+8],ch		       ;store second digit
	mov byte ptr [di+9],0b8h
	;now print the start time
	inc si
	mov AL,[SI]		       ;GET start hour
	mov CH,AL
	shr AL,4
	add al,30h
	mov [di+10],al		       ;store first digit
	and ch,0FH
	add ch,30h
	mov [di+11],ch		       ;store second digit
	;next comes year
	mov byte ptr [di+12],':'       ;print colon between hour and minute
	inc SI
	mov AL,[SI]		       ;GET start minute
	mov CH,AL
	shr AL,4
	add al,30h
	mov [di+13],al		       ;store first digit
	and ch,0FH
	add ch,30h
	mov [di+14],ch		       ;store second digit
	mov byte ptr [di+15],0bbh
	;now print the end time
	inc si
	mov AL,[SI]		       ;GET end hour
	mov CH,AL
	shr AL,4
	add al,30h
	mov [di+16],al		       ;store first digit
	and ch,0FH
	add ch,30h
	mov [di+17],ch		       ;store second digit
	;next comes year
	mov byte ptr [di+18],':'       ;print colon between hour and minute
	inc SI
	mov AL,[SI]		       ;GET end minute
	mov CH,AL
	shr AL,4
	add al,30h
	mov [di+19],al		       ;store first digit
	and ch,0FH
	add ch,30h
	mov [di+20],ch		       ;store second digit
	mov byte ptr [di+21],0ffh
DirEntryDone:
	mov si,offset testmsg
	mov cl,1
	mov bx,WSPointer
	call prant11

	mov BX,WSPointer     ;move screen address one line down
	add BX,1120
	mov WSPointer,BX
	inc DIRNUM		       ;increase record number
	mov AL,DIRNUM
	cmp AL,64		       ;last one?
	je @F			       ;if so, jump forward
	and AL,0FH		       ;last on this windowfull?
	jnz DIRLP2		       ;if not, jump back
	call PTAILR		       ;print tail message
	call PrintArrow
	jmp KeyDone		       ;finish
@@:
	mov DIRFLG,01H		       ;ALL PRINTED
	call PrintArrow
	jmp KeyDone

DIROFF: ;SWITCH BACK TO NORMAL MODE
	call killws
	jmp KeyDone

NOFILE:
	;prints 'no more records' and signals directory done
	mov BX,WSPointer
	add BX,2560
	mov di,offset NoFilesMessage
	call CopyMessage
	mov cl,1
	call prant11
	mov DIRFLG,01H
	call PrintArrow
	jmp KeyDone

StartAutoRec:
	call VerifyForRead		       ;VERIFY For READ
	jc KeyDone
	call rsense
	call VerifyForWrite	       ;is it write protected?
	jne KeyDone
	;put in record name as 'Autostart'
	mov di,offset AnBuff
	mov dword ptr [di],'otuA'
	mov dword ptr [di+4],'rats'
	mov dword ptr [di+8],0ff74h
	mov ancur,9
	jmp AStart1



SRECOL: ;this starts Record mode

	test StorageMode,01H		       ;is Play mode on?
	je @F			       ;if so, Rebuke and abort
	mov si,offset ErrorMsg8        ;'in play mode'
	call Rebuke
	jmp KeyDone
@@:
	call VerifyForRead		;VERIFY For READ
	jnc @f
	mov si,offset ErrorMsg7 	;'no disk'
	call Rebuke
	jmp KeyDone
@@:
	call rsense
	call VerifyForWrite		;is it write protected?
	je @f
	mov si,offset ErrorMsg2        ;'write protected'
	call Rebuke		       ;Rebuke if so
	jmp KeyDone
@@:
	test StorageMode,02H		       ;IS RECORD ACTIVE
	jne FollowOnRec 	       ;iF SO, JUMP to follow on
AStart1:
	call rsense
	;the directory is loaded from the disk
	;call PRMERE		       ;lock the disk in the drive
	call LDIRS		       ;LOAD THE DIRECTORY SECTORS
	jnc @f
	mov si,offset ErrorMsg41
	call Rebuke
	jmp KeyDone
@@:

	mov CL,0
	mov SI,offset DIRSEC	       ;BEGINING OF DIRECTORY
@@:
	cmp byte PTR [SI],00H	       ;IS SLOT VACANT?
	je @f			       ;IF SO JUMP
	add SI,020H		       ;set pointer to next entry
	inc cl
	cmp cl,63		       ;63 entrys
	jne @B			       ;loop back
	;no vacant directory space exists: Rebuke and abort
	mov si,offset ErrorMsg9        ;'disk full'
	call Rebuke
	jmp KeyDone

@@:	;a spare directory space has been found at [si]

	mov CURREC,cl		       ;store it as the current record no.
	;DIRECTORY FORMAT
	;each entry in the directory consists of 32 bytes
	;they are defined as follows
	;00	0=no record	1=record is valid   2=volume name
	;01-12	record or volume name
	;13	day
	;14	month
	;15	year
	;16	start hour
	;17	start minute
	;18	end hour
	;19	end minute
	;20-23	start cluster
	;24-27	end cluster

	mov byte PTR [SI],01h	       ;mark valid record
	inc SI
	;if a record name is suppied, copy to directory
	mov bx,(offset testmsg+3)      ;copy name into testmsg
	cmp AnCur,0		       ;ready for StatusRecord
	je NoRecName
	mov CH,12		       ;get record name from
	mov DI,offset ANBUFF	       ;annotation buffer
@@:
	mov AL,[DI]
	mov [SI],AL
	mov [bx],al
	inc bx
	inc DI
	inc SI
	dec CH
	jnz @B
	jmp @f

NoRecName:
	mov al,0ffh
	mov [bx],al
	mov [si],al
	add si,12

	;now get the date from the real time clock
@@:
	mov AL,07H
	out 070H,AL
	IN AL,071H		       ;get day
	cmp AL,0FFH		       ;if this or any other value from
	je @B			       ;the clock is 0ffh, try again
	mov [SI],AL		       ;fill it in
	inc SI
@@:
	mov AL,08H
	out 070H,AL
	IN AL,071H		       ;get month
	cmp AL,0FFH
	je @B
	mov [SI],AL
	inc SI
@@:
	mov AL,09H
	out 070H,AL
	IN AL,071H		       ;get year
	cmp AL,0FFH
	je @B
	mov [SI],AL

	add SI,5
	;now get the starting sector

	mov EBX,0000H
	cmp CL,0		       ;IS IT THE FIRST RECORD?
	je @F			       ;IF SO, START sector is 0

	mov EBX,[SI-28]		       ;OTHERWISE IT IS LAST RECORDS
	inc EBX
@@:				       ;STOP LINE+1
	mov [SI],EBX		       ;start and end clusters are the same
	mov [si+4],ebx		       ;to start with
	mov CurrentCluster,EBX	       ;INSERT START CLUSTER
	mov StartCluster,ebx	       ;update this
	;the directory entry has now been filled in
	mov StorageMode,02H	       ;TURN RECORD MODE ON
	test SwapMode,1 	       ;if swap mode is on, don't
	jne @f			       ;update reline
	mov AX,DLINE
	mov RELINE,AX
@@:
	mov SwapMode,0
	mov AL,HOURS		       ;fill in start time
	mov [SI-4],AL		       ;fill in the end time as the start
	mov [si-2],al		       ;time in case of power failure before
	mov AL,MINUTES		       ;the first update
	mov [SI-3],AL		       ;same for minutes
	mov [si-1],al
	;it is saved back to the disk
	call WDIRS		       ;SAVE DIRECTORY
	cmp AL,00H		       ;is there an error?
	je @F
	mov StorageMode,00H		       ;if so, kill record mode
	jmp KeyDone		       ;abort
@@:
	mov al,CurRec
	call StatusRecord
	call StatusMode		       ;UPDATE STATUS LINE
	or FeatureFlag,040h	       ;record delineation mark
	JMP FUNS2		       ;CLEAR ANNO BOX

RECOFF: ;this turns the record mode off
	call RecordModeOff
	call ClearFilename
	jmp KeyDone

RecordModeOff:
	;this turns Record mode off and tidys up the directory
	call LDIRS			;LOAD DIRECTORY SECTORs
	mov StorageMode,00H		;TURN RECORD MODE OFF
	call StatusMode			;UPDATE STATUS LINE
	mov bl,CURREC			;find the entry offset in the
	mov bh,0			;directory from 'currec'
	shl bx,5
	lea si,dirsec[bx]
	mov AL,HOURS			;fill in stop hours
	mov [SI+18],AL
	mov AL,MINUTES			;and minutes
	mov [SI+19],AL
	mov EBX,CurrentCluster		;and stop cluster
	mov [SI+24],EBX
	call WDIRS		       ;save the directory
	ret			       ;done

FollowOnRec:
	;this is called when RECORD is pressed when already in
	;Record mode
	;the current record is stop and a new one started
	;first the current record is stopped
	call RecordModeOff
	;now switch it back on
	jmp srecol


SPLAY:
	;called when 'PLAY' is pressed
	test StorageMode,02H		       ;IS IT IN RECORD MODE?
	je @F
SPLYER:
	mov si,offset ErrorMsg8        ;'in play mode'
	call Rebuke		       ;IF SO, DO NOTHING
	jmp KeyDone
@@:
	;call PRMERE
	call VerifyForRead		       ;make sure a disk is in
	jnc @f
	mov si,offset ErrorMsg7        ;'no disk'
	call Rebuke
	jmp KeyDone
@@:
	test StorageMode,01H		       ;IS PLAY MODE ACTIVE?
	je PLAY69		       ;IF NOT, JUMP FORWARD

	test PAUSEF,01H		       ;if pause is not active jump
	je @F
	mov PAUSEF,00H		       ;turn pause off
	mov FORWAD,00H		       ;turn cue off
	mov FWDINC,01H
	call StatusMode 	       ;'Play'
	jmp KeyDone

@@:				       ;turn cue off
	test FORWAD,01H
	je SPLYER		       ;error
	JMP CUEOFF


PLAY69:
	;if play mode was off, come here
	mov SequenceFlag,00H	       ;clear sequence flag
	mov SequenceCount,01H	       ;and count
	test SETTMF,01H 	       ;IS TIME READY?
	jne PLAYGO		       ;IF SO, JUMP
	;get record number
	call LDIRS		       ;LOAD THE DIRECTORY SECTORS
	jnc @f
	mov si,offset ErrorMsg41
	call Rebuke
	jmp KeyDone
@@:
	mov si,offset anbuff
	mov al,0
	cmp byte ptr [si],'X'		;play V4 record?
	jne @f
	inc al
	inc si
@@:
	mov ReadFormat,al
	call GetDecimal
	jnc @f
	cmp cl,0		       ;no number
	jne BadRecNo
	mov AL,LASTRN		       ;IF SO, USE LAST RECORD NUMBER+1
	inc AL
	mov LASTRN,AL
	JMP OLDRN
@@:				       ;GET NEW NUMBER
	mov al,dl
	dec AL			       ;RECORD NUMBER HERE IN AL
OLDRN:
	mov AnnotationUsed,01H
	cmp AL,63		       ;63 records max
	Jbe @F
BadRecNo:
	mov si,offset ErrorMsg11       ;'invalid record'
	call Rebuke
	jmp KeyDone
@@:
	mov LASTRN,AL
	mov CURPLY,AL		       ;CURRENT PLAY NUMBER
	mov AH,00H
	shl AX,5
	mov SI,offset DIRSEC
	add SI,AX
	mov al,[si]
	and al,0fh			;get record type
	cmp al,01h			;sonar record?
	jne INVALD			;IF NOT, ABORT
	test byte ptr [si],10h		;old 20m max record?
	je @f
	or ReadFormat,3
@@:
	mov StorageMode,01H		;TEMP PLAY ON
	call StatusMode			;UPDATE STATUS LINE
	mov StorageMode,00H		;PLAY OFF
	mov AL,(DOSINTMASK OR 029h)	;SWITCH OFF UART, nav and TIMEOUT
	out 021H,AL			;interrupt
	mov SonarWasOn,00H
	mov SonarIsOn,00H
	movzx bx,curply
	shl bx,5
	cmp byte ptr dirsec[bx+13],0	;is the record an edit? (date=0)
	jne @f
	mov ancur,0
	jmp NoTimeNeeded
@@:
	mov SETTMF,01H		       ;GET TIME
	mov di,offset ptmmsg	       ;'Enter time?'
	call petext

	mov ANCUR,00H
	jmp KeyDone

PLAYGO:
	mov di,offset tspace
	call petext
	call LDIRS		       ;RELOAD DIRECTORY (COULD BE ALTERED)
NoTimeNeeded:
	mov StorageMode,01H	       ;TURN PLAY MODE ON
	cmp WindowFlag,00h	       ;if a window is present, clean up
				       ;window before playing
	je @F
	call killws
@@:
	movzx si,CURPLY
	shl si,5
	add SI,offset DIRSEC
	mov EAX,[SI+24]		       ;STOP CLUSTER
	mov StopCluster,EAX	       ;STORE IT
	mov EAX,[SI+20]		       ;GET START CLUSTER
	mov CurrentCluster,EAX	       ;STORE IT
	mov StartCluster,EAX	       ;STORE START For REPEAT
	;NOW GET SEARCH TIME
	cmp ANCUR,00H		       ;IF NO TIME ENTERED START AT START
	je NSTIME
	cmp ANCUR,5		       ;IF INCOMPLETE, ABORT
	jne PABORT
	mov DI,offset ANBUFF
	mov AL,[DI]
	sub al,30h
	shl AL,4
	add AL,[DI+1]
	sub al,30h
	cmp AL,023H		       ;ABORT IF HOUR > 23 (BCD)
	JA PABORT
	mov SHOUR,AL
	mov AL,[DI+3]
	sub al,30h
	shl AL,4
	add AL,[DI+4]
	sub al,30h
	cmp AL,059H
	JA PABORT		       ;ABORT IF MINUTE > 59 (BCD)
	mov SMIN,AL
	;NOW CHECK IF TIME IS WITHIN LIMITS
	mov ax,[si+18]		       ;stop time
	xchg al,ah		       ;ah=hours, al=mins
	mov bx,[si+16]		       ;start time
	xchg bl,bh
	mov bp,bx		       ;save start in bp for later
	cmp AX,BX		       ;COMPARE WITH START TIME
	jae SameDay		       ;IF STOP < START add 24 HOURS
	add ah,24h		       ;to the stop time
	cmp word ptr SMin,bx	       ;if the search time < start time
	jae SameDay		       ;add 24 hours to it
	add SHour,24h
SameDay:
	cmp AX,WORD PTR SMIN	       ;ABORT IF SEARCH TIME>STOP TIME
	jb PABORT
	cmp BX,WORD PTR SMIN	       ;ABORT IF SEARCH TIME<START TIME
	JA PABORT
	;NOW SEARCH For SECTOR
	mov EAX,[SI+24] 	       ;stop cluster
	mov EDX,[SI+20] 	       ;start cluster
	SUB EAX,edx
	shr EAX,2		       ;search step=(stop-start)/4
	add EDX,[SI+24]
	RCR EDX,1		       ;HUNT SECTor = (START+STOP)/2
	mov SearchStep,EAX
	mov CurrentCluster,EDX
SRCHLP:
	call LSSEC		       ;load cluster
	mov SI,offset SRCHBF
	mov ax,[si+0f80h]	       ;get time from cluster in ax
	xchg al,ah
	cmp ax,bp		       ;if this is < start, add 24 hours
	jae @f
	add ah,24h
@@:
	mov EBX,SearchStep
	cmp AX,WORD PTR SMIN	       ;if this is less than the search
	jae @F			       ;time, add the step to the cluster
	add CurrentCluster,EBX
	JMP SRCH1
@@:
	SUB CurrentCluster,EBX	       ;else subtract it
SRCH1:
	shr EBX,1
	mov SearchStep,EBX
	jne SRCHLP		       ;finish when the step is zero

NSTIME:
	call CLRBOX
	call WriteFilename
	mov SETTMF,00H
	jmp KeyDone

INVALD:
	mov si,offset ErrorMsg12       ;'invalid number'
	call Rebuke
	jmp KeyDone


SSTOP:
	mov DiskAlarm,0 	       ;re-enable disk alarm
	mov SwapMode,0		       ;kill swap mode
	test StorageMode,01H		       ;IS PLAY MODE ON?
	jne PLYOFF		       ;IF SO, STOP IT
	test StorageMode,02H		       ;IS RECORD MODE ON?
	jne RECOFF		       ;IF SO, STOP IT
	call StatusMode
	jmp KeyDone


PABORT:
	mov AnnotationUsed,1
	mov si,offset ErrorMsg13       ;'invalid time'
	call Rebuke

PLYOFF:
	mov PAUSEF,00H
	mov StorageMode,00H		       ;TURN PLAY MODE OFF
	call StatusMode		       ;UPDATE STATUS LINE
	call ClearFilename
	mov FORWAD,00H
	mov FWDINC,01H

	IF DOS			       ;interrupts
	mov AL,DOSINTMASK		       ;UART(5) MOUSE(4) keyboard(1)  nav(3)
	ELSE			       ;cascade(2)
	mov al,REPINTMASK		       ;mouse (4) keyboard (1)
	ENDIF

	out 021H,AL		       ;ENABLE UART, nav interrupt
	mov SETTMF,00H
	jmp KeyDone

GetDecimal:
	;this gets a decimal value from the string at [si]
	;the value is returned in dx
	;carry is set if there is an error
	xor dx,dx		       ;zero start value
	mov cl,0
GetDecLoop:
	movzx ax,byte ptr [si]	       ;get character
	cmp al,0ffh		       ;end of string
	je GetDec2		       ;finish if so
	cmp al,','		       ;end of string
	je GetDec2		       ;finish if so
	cmp al,'.'		       ;decimal point?
	je GetDec3		       ;jump if so
	cmp al,' '		       ;and any spaces
	je @f
	shl dx,1
	jc GetDec1		       ;overflow
	mov bx,dx
	shl dx,2
	jc GetDec1		       ;overflow
	add dx,bx		       ;multiply dx by 10
	jc GetDec1		       ;overflow
	cmp al,'0'		       ;check digit is in range
	jb GetDec1
	cmp al,'9'
	ja GetDec1
	sub al,'0'
	add dx,ax		       ;add into total
	jc GetDec1		       ;overflow
	inc cl
@@:
	inc si
	jmp GetDecLoop
GetDec2:
	cmp cl,0
	je GetDec1
	mov cl,0
	clc
	ret
GetDec1:
	stc
	ret

GetDec3:
	;come here if a decimal point occours
	;get the digit after the point in cl
	mov al,[si+1]
	mov cl,0
	cmp al,'0'		       ;check digit is in range
	jb @f
	cmp al,'9'
	ja @f
	sub al,'0'
	mov cl,al
@@:
	clc
	ret

FindParameter:
	;this finds a parameter in the string [si] after cl commas
	mov ch,60		       ;max string length
FindParam1:
	mov al,[si]		       ;get char
	inc si
	cmp al,0ffh		       ;end of string?
	je FindParam2		       ;fail
	cmp al,','
	je @f			       ;jump if comma found
	dec ch
	jnz FindParam1		       ;fail after 32 characters
FindParam2:
	stc			       ;set carry if it has failed
	ret

@@:
	dec cl			       ;comma count
	jnz FindParam1
	clc			       ;si points at byte after
	ret			       ;the cl'th comma




ERASED: ;THIS CLEARS THE DIRECTORY SECTOR
	test StorageMode,03H		       ;IF RECORD or PLAY, IGNORE
	je @F
	jmp KeyDone
@@:
	mov CX,4096
	mov SI,offset DIRSEC
@@:
	mov byte PTR [SI],00H
	inc SI
	LOOP @B
	call WDIRS
	RET

PHEADR: ;THIS PRINTS THE HEADER For THE DIRECTORY LISTING EG.
	;DIRECTORY of disk: (volume name)
	;
	;NUMBER   NAME		DATE	   START TIME  END TIME
	; 1	  FISH HEADS	12/12/92   15:32       16:07

	mov di,offset DirHeaderMessage1
	call CopyMessage
	;get volume name
	mov di,(offset dirsec+2016)
	add si,21
	mov eax,[di+1]
	mov ecx,[di+5]
	mov dx,[di+9]
	cmp byte ptr [di],02h
	je @f
	;no volume name
	mov eax,'tnu('
	mov ecx,'elti'
	mov dx,')d'
@@:
	mov [si],eax
	mov [si+4],ecx
	mov [si+8],dx
	mov si,offset testmsg
	push bx
	mov cl,1
	call prant11		       ;print the text
	pop bx
	push bx
	mov di,offset MediaSizeMessage
	call CopyMessage
	mov eax,'M821'
	cmp MediaType,0
	je @f
	mov eax,'M032'
	cmp MediaType,1
	je @f
	mov eax,'M046'
@@:
	mov [si+13],eax
	add bx,40
	call Prant11			;print media size
	call StatusDate 		;current date
	pop bx
	add bx,2240
	mov di,offset DirHeaderMessage2
	call CopyMessage
	mov cl,1
	mov WSPointer,bx
	call prant11		       ;print the text
	RET

PTAILR: ;this prints the message at the bottom of an incomplete
	;directory screen
	;"press Q to cancel,  or DIRECTORY for more"
	call SCRNAD
	add BX,36167
	mov di,offset DirTailMessage
	call CopyMessage
	mov cl,1
	call prant11
	RET

WriteDate:
	;this writes the string (day) (month) (year)
	;at [di]
	mov word ptr [di+8],0ff7ch
@@:
	mov al,0ah		       ;if the real time clock is
	out 070h,al		       ;updating the time, bit 7 of
	in al,71h		       ;byte 0ah is set and the time
	test al,80h		       ;should not be read
	jne @b

	mov AL,07H
	out 070H,AL
	IN AL,071H		       ;get day

	mov CH,AL
	shr AL,4		       ;FIRST DIGIT
	add al,30h
	cmp al,'0'		       ;blank out leading zeros
	je @f
	mov [di],al
	inc di
@@:
	and ch,0FH
	add ch,30h
	mov [di],ch		       ;second digit

	mov AL,08H
	out 070H,AL
	IN AL,071H		       ;get month
	;next comes month
	mov byte ptr [di+1],'_'	       ;print space between day and month
	mov bl,al
	;the month is printed in a three letter abbreviation eg 'Jan'
	;it is stored in bcd format
	cmp bl,9		       ;first convert to binary fromat
	jbe @f
	sub bl,6
@@:
	dec bl
	mov bh,0
	shl bx,2		       ;dword pointer
	mov eax,dword ptr fs:MonthNames[bx]
	mov [di+2],eax
	;next comes year
	mov AL,09H
	out 070H,AL
	IN AL,071H		       ;get year
	mov CH,AL
	shr AL,4
	add al,30h
	mov [di+6],al		       ;store first digit
	and ch,0FH
	add ch,30h
	mov [di+7],ch		       ;store second digit
	ret

CUEON:
	cmp StorageMode,01H		       ;ONLY WORKS IN PLAY MODE
	jne CUEER
	test pausef,1		       ;is pause on?
	jne @f			       ;if so, switch cue on
	test FORWAD,01H 	       ;IS CUE ALREADY ON?
	je @F			       ;if so, signal error
	mov si,offset ErrorMsg14       ;'in cue mode'
	call Rebuke		       ;Rebuke IF SO
	jmp KeyDone
@@:
	mov pausef,00h
	mov FORWAD,01H		       ;OTHERWISE SWITCH IT ON
	mov FWDINC,04H
	call StatusMode
	jmp KeyDone

CUEOFF:
	mov FORWAD,00H
	mov FWDINC,01H
	call StatusMode
	jmp KeyDone

cueer:
	mov si,offset ErrorMsg15	;'wrong mode'
	call Rebuke
	jmp KeyDone

PAUSE:
	cmp StorageMode,01H
	jne @F
	cmp PAUSEF,01H
	je @F
	mov PAUSEF,01H
	call StatusMode
	jmp KeyDone
@@:
	mov si,offset ErrorMsg15	;'wrong mode'
	call Rebuke
	jmp KeyDone


COPY:	;COPY THE CURRENT SCREEN TO ANOTHER disk
	;USING THE GIVEN NAME
	;only the visible screen is copied
	test StorageMode,03H	       ;is it in play or record mode?
	je @f			       ;error if so
	mov si,offset ErrorMsg15       ;'wrong mode'
	call Rebuke
	jmp KeyDone
@@:
	call VerifyForRead	       ;make sure a disk is in
	jnc @f
	mov si,offset ErrorMsg7        ;'no disk'
	call Rebuke
	JMP EditFinish
@@:
	call LDIRS		       ;LOAD THE DIRECTORY SECTORS
	jnc @f
	mov si,offset ErrorMsg41
	call Rebuke
	jmp KeyDone
@@:

	call VerifyForWrite	       ;check write permission
	je @f
	mov si,offset ErrorMsg2	       ;'write protected'
	call Rebuke
	jmp EditFinish
@@:
	mov EditOnFlag,1	       ;signal edit on
	mov AnnotationUsed,1
	call StatusMode		       ;print 'Edit' mode

	mov CL,0
	mov SI,offset DIRSEC	       ;BEGINING OF DIRECTORY
@@:
	cmp byte PTR [SI],00H	       ;IS SLOT VACANT?
	je @f			       ;IF SO JUMP
	add SI,020H		       ;increase pointer to next entry
	inc cl
	cmp cl,63		       ;63 entrys max
	jne @B			       ;if count reaches zero, directory
	;ERROR: disk DIRECTORY FULL    ;is full
	mov si,offset ErrorMsg9        ;'disk full'
	call Rebuke
	jmp EditFinish

@@:	;A DIRECTORY SLOT HAS BEEN FOUND For A COPY

	mov CURREC,cl		       ;CURRENT RECORD NUMBER

	mov byte PTR [SI],01H	       ;SIGNAL 'VALID RECORD'
	inc SI
	mov CH,12		       ;COPY 12 CHARS For NAME
	mov DI,offset ANBUFF	       ;FROM ANNOTATION BUFFER
@@:
	mov AL,[DI]
	mov [SI],AL
	inc DI
	inc SI
	dec CH
	jnz @B
	add SI,7
	mov EBX,0000H
	cmp CL,0		       ;IS IT THE FIRST RECORD?
	je @F			       ;IF SO, START LINE IS 0
	mov EBX,[SI-28]		       ;OTHERWISE IT IS LAST RECORDS
	inc EBX
@@:				       ;STOP LINE+1
	mov [SI],EBX
	mov CurrentCluster,EBX	       ;INSERT START CLUSTER
	;start and stop times are not needed for an 'edit'
	mov byte ptr [SI-7],0	       ;set day to 0 to mark 'edit'
	;now work out the length of the edit
	;it is from the top to the last visible line
	;ie ScreenLineMap[427]
	mov ax,cline			;get top of screen
	sub ax,ScreenLineMap[850]	;get size of screen
	and ax,BufferLimit		;wrap round
	;ax now holds the number of visible buffer lines
	and ax,0fff0h			;to the nearest 16 lines
	mov EditSize,ax
	movzx eax,ax
	;DIRECTORY INFO NOW FILLED IN
	add EBX,eax
	mov [SI+4],EBX
	call WDIRS		       ;SAVE DIR
	call WriteEditClusters	       ;write edit screen to disk
EditFinish:
	mov EditOnFlag,0
	call StatusMode
	jmp KeyDone


GetDistance:
	;this finds the range in 0.1 metres from the centreline
	;to the arrow tip
	mov bx,MouseYCoord		       ;get y co-ordinate
	shl bx,1
	mov ax,ScreenLineMap[bx]
	;ax now holds the buffer line that the arrow is on
	shl AX,3		       ;calculate segment
	add AX,038H
	mov gs,ax
	mov cl,gs:[0f83h]	       ;get range from line
	mov ch,cl		       ;save in ch for later
	and cl,0fh		       ;mask out frequency bit

	mov bx,75		       ;150m
	cmp cl,3
	je @f

	mov bx,62
	cmp cl,2		       ;125m
	je @f

	mov bx,50
	cmp cl,1		       ;100m
	je @f

	mov bx,25		       ;50m
	cmp cl,0
	je @f

	mov bx,100
	cmp cl,4		       ;200m
	je @f

	mov bx,150
	cmp cl,5		       ;300m
	je @f

	mov bx,200		       ;400m
	cmp cl,6
	je @f

	mov bx,37		       ;75m
	cmp cl,7
	je @f

@@:
	;range dependent multiplier in bx
	mov ax,MouseXCoord	       ;get mouse x position (0-639)
	test ManualAltitude,1
	je @f
	add ax,16
@@:
	test ScreenZoom,1	       ;if there is no zoom on
	je GetDist1		       ;jump ahead, ignoring pan
	shr ax,1		       ;otherwise divide pan by 2
	test ScreenZoom,4		       ;if zoom is x 2, jump ahead
	je @F			       ;otherwise divide pan by 2 again
	shr ax,1
@@:				       ;add in the pan position*40
	mov ch,ScreenPan
	shl ch,1
	mov cl,ch
	shl ch,2
	add cl,ch
	mov ch,0
	shl cx,2
	add ax,cx
GetDist1:
	;distance in 640ths in ax
	;convert to metres
	mov ecx,'dbtS'		       ;dword 'Stbd'
	sub ax,322
	jnc @f
	mov ecx,'troP'		       ;dword 'Port'
	neg ax
@@:
	mul bx
	shr ax,4
	;ax now in metres/10
	;cl='P' for port, 'S' for starboard
	ret


InitializeValues: ;SET INITIAL VALUES For VARIABLE DATA
	mov SI,offset DSBEG
	mov CX,(offset DSPROTF-offset DSBEG)
	mov AL,00H		       ;FIRST SET ALL VARIABLES TO 0
@@:
	mov [SI],AL
	inc SI
	LOOP @B
	;now set up CMOS flags using byte 3 of the cmos ram
	mov al,3
	out 70h,al
	nop
	nop
	in al,71h
	mov DisplayFlags,al
	mov ScreenPan,04H
	mov lastrn,0ffh
	mov AlarmControl,0ffh	       ;enable altitude alarm
	mov Speed,15		       ;speed=1.5m/s
	mov al,1
	mov AnnotationUsed,al
	mov CacheOff,0
	mov al,0ffh
	mov INVPAL,al		       ;normal video
	mov Altitude,al
	mov RangeNumber,10	       ;no valid range HF fish
	mov STCAP,99
	mov RegisterNumber,9
	mov ax,50000
	mov ARROW,ax
	mov CursorAddress,ax
	mov RemoveAddress,ax
	mov CoaxPulse,3000
	mov AX,01H
	mov TelemetryReady,AL
	mov FWDINC,AX
	mov ax,320
	mov CursorXCoord,ax
	mov ax,180
	mov CursorYCoord,ax
	;set up default colour schemes
	IF PSEA
	call LoadScheme
	jnc ColoursLoaded
	ENDIF
	mov si,offset DefaultColours
	mov di,offset MonoScheme
	mov cl,18
@@:
	mov al,fs:[si]
	mov [di],al
	inc si
	inc di
	dec cl
	jnz @b
ColoursLoaded:
	mov SI,offset ANBUFF
	mov CL,13
	mov AL,0FFH
@@:
	mov [SI],AL
	inc SI
	dec CL
	jnz @B
	mov SI,offset ETBUFF
	mov byte PTR [SI+5],0FFH
	mov al,88h
	mov Hours,al
	mov Minutes,al
	mov Seconds,al
	mov AutoStart,2
	mov DeskJetDPI,0
	mov PS2Count,0ffh
	RET


SETCOL: 			       ;SETS UP THE FIRST 16
	push ES 		       ;COLOUR REGISTERS
	mov BP,FSEG		       ;TO A GREY SCALE
	mov ES,BP		       ;STORED IN 'COLOUR'
	mov AX,01012H
	mov BX,00
	mov CX,020H
	mov DX,offset ColourTable
        INT 010H
	pop ES
	RET

SETPAL: ;SET UP THE 16 PALETTE REGISTERS
	mov DX,3DAH		       ;CLEAR FLIP-FLOP
	IN AL,DX
	mov DX,3C0H		       ;POINT TO COLOUR SELECT REGISTER
	mov CL,0
	mov ah,DisplayFlags
	and ah,080h
	shr ah,3
@@:
	mov AL,CL
	out DX,AL
	Xor AL,0fh
	add al,ah
	out DX,AL
	inc CL
	cmp CL,16
	jne @B
	mov AL,20H
	out DX,AL
	RET

PDLINE: ;THIS PRINTS THE COMPLETED LINE AT THE TOP OF THE SCREEN
	mov RedrawLine,0	       ;SIGNAL NOT A REDRAW LINE
	mov AX,DLINE		       ;SOURCE LINE IS DLINE
	call PLINE		       ;PRINT THE LINE
	cmp ScrollDrop,0	       ;was anything printed?
	je nodapfill		       ;if not, jump ahead
	movzx cx,ScrollDrop	       ;number of lines printed
	add RedrawMapLine,cx	       ;compensate redraw line
	mov ax,dline		       ;add redraw screen line to
	mov bx,0		       ;word pointer
@@:
	mov ScreenLineMap[bx],ax       ;fill screen line map
	add bx,2
	loop @b
nodapfill:
	call ScrnAd
	add bx,4160
LookBEnter:
	mov DoneLineAddress,bx
	test LFeatures,0cfh	       ;are there any features?
	je FeaturesDone		       ;if not, jump ahead
	test HideShowFlag,1	       ;are features to be shown?
	jne FeaturesDone	       ;jump if not
	test HideMouse,1
	jne @f
	call RemoveArrow
@@:
	test LFeatures,040H	       ;is there a delineation mark?
	je @F
	mov BX,DoneLineAddress	       ;top of THE SCREEN
	call PrintDelineation
@@:
	test LFeatures,02H	       ;IS THERE ANNOTATION?
	Je @F
	test DisplayFlags,01H	       ;is annotation visible?
	je @F
	mov BX,DoneLineAddress	       ;TOP OF WINDOW
	call PANNO		       ;PRINT THE ANNOTATION
@@:
	test LFeatures,01H	       ;IS THERE A event MARK?
	je @F
	test DisplayFlags,8	       ;are they visible?
	je @f			       ;if not, jump
	mov BX,DoneLineAddress	       ;THE SCREEN
	call PMark		       ;print black line
	mov ax,LVNumber		       ;GET EVENT MARK NUMBER
	mov SI,offset LAnnotation	;build text in 'LAnnotation'
	mov bx,ax
	and ax,0f0fh
	and bx,0f0f0h
	shr bx,4
	add ax,3030h
	add bx,3030h
	xchg al,bh
	mov [si],ax
	mov [si+2],bx
	mov byte PTR [SI+4],0FFH       ;STRING TERMINATOR
	mov BX,DoneLineAddress	       ;GET SCREEN addRESS
	call PRANN2		       ;PRINT IT
@@:
	test LFeatures,08h	       ;is there nav data?
	je nonavp
	test DisplayFlags,4	       ;is nav data on?
	je nonavp
	;print 32 bytes of nav data from gs:[0fc0h-0fdfh]
	;first copy the string from 'dline' to NavDataString
	mov di,offset NavDataString
	push di
	call UnCompress
	pop si
	test DisplayFlags,10h		;is position data only on?
	jne @f				;if not, print all
	mov di,offset NavDataString
	call ValidNavString
	jc NoNavP
@@:
	mov bx,DoneLineAddress
	call fixan		       ;print the nav data
nonavp:
	test LFeatures,04H	       ;IS THERE A TIME MARK
	jz NOTIME		       ;IF NOT, SKIP
	mov ax,LTime
	call EXTIME
	mov BX,DoneLineAddress
	add bx,76
	mov SI,offset ETBUFF
	call FIXAN			;print time mark

NOTIME:
	test LFeatures,080H	       ;IS THERE A Altitude MARK?
	jz NOHGTM		       ;IF NOT, SKIP
	test DisplayFlags,02H	       ;ARE THEY ACTIVE?
	jz NOHGTM		       ;IF NOT, SKIP
	movzx ax,LAltitude	       ;Altitude IN AL
	shl ax,1		       ;double altitude
	mov BL,25
	shl AX,1
	DIV BL
	aam			       ;split into tens and units
	add ax,3030h
	mov SI,offset LAnnotation      ;build text in 'LAnnotation'
	cmp ah,'0'		       ;is first digit zero?
	jne @f
	mov ah,' '		       ;if so, replace with space
@@:
	mov [SI],AH

	mov [SI+1],AL
	mov byte PTR [SI+2],'m'	       ;print 'xxm'
	mov byte PTR [SI+3],0FFH
	mov LAnPosition,80	       ;CENTRE OF SCREEN
	mov BX,DoneLineAddress	       ;TOP OF WINDOW
	call PANNO		       ;PRINT Altitude MARK
NOHGTM:
	test HideMouse,1
	jne FeaturesDone
	call PrintArrow
FeaturesDone:
	test RedrawLine,1	       ;jump if called from lookback
	jne @f
	mov AX,DLINE		       ;INCREASE DLINE
	inc AX
	and ax,BufferLimit
	mov DLINE,AX
@@:
	RET

PRLINE: ;THIS PRINTS A REDRAW LINE AT addRESS RedrawAddress
	call SCRNAD		       ;first see if the redraw is done
	mov ax,RedrawAddress	       ;redraw address in ax, screentop in bx
	sub ax,bx		       ;get difference in ax
	mov dx,038400		       ;38400=draw to bottom of screen
	test WindowFlag,0ffh		;never redraw lower screen if a
	jne @f				;window is active
	cmp LookBackScrl,1
	je Nortfr
	cmp FreezeMode,1	       ;if freeze=1 (zoom window sets
	jne NORTFR		       ;freeze=3)
	cmp NewCurZoom,2
	je NoRTFr
	;freeze is on
@@:
	mov dx,8960		       ;8960=draw to bottom of active window
NORTFR:
	cmp ax,dx		       ;if the redraw has got to the bottom
	jbe @f			       ;of the screen, stop it
	stc			       ;carry set if done
	ret
@@:
	mov RedrawLine,1	       ;SIGNAL REDRAW LINE
	mov AX,RLINE		       ;SOURCE LINE IS RLINE
	call PLINE		       ;PRINT THE REDRAW LINE
	;now update the screen map
	cmp ScrollDrop,0	       ;if no lines were printed
	je nomapfill		       ;or the cursor zoom is on
	cmp FreezeMode,3	       ;then don't update the screen map
	je NoMapFill
	movzx cx,ScrollDrop	       ;number of lines printed
	mov ax,rline		       ;add redraw screen line to
	mov bx,RedrawMapLine	       ;get index number
	add RedrawMapLine,cx
	shl bx,1		       ;word pointer
@@:
	mov ScreenLineMap[bx],ax       ;fill screen line map
	add bx,2
	loop @b
nomapfill:
	test LFeatures,0cfh	       ;are there any features?
	je nonavdt		       ;if not, jump ahead
	test HideShowFlag,1
	jne nonavdt
	test LFeatures,040H	       ;is there a delineation mark?
	je @F			       ;IF NOT, SKIP
	mov BX,RedrawAddress		       ;otherwise print a mark
	add bx,50h
	call PrintDelineation
	add RedrawAddress,160
@@:
	test LFeatures,01H	       ;IS THERE AN EVENT MARK?
	je @F			       ;IF NOT, SKIP
	test DisplayFlags,8	       ;are they on?
	je @f			       ;if not, jump
	mov BX,RedrawAddress		       ;PRINT IT
	SUB BX,050H
	mov VaddR,BX
	call PMARK
	mov ax,LVNumber 		;STORE EVENT MARK NUMBER
	mov TVNumber,ax
	mov VFLAG,01H		       ;SET PENDING FLAG
@@:
	test LFeatures,04H	       ;IS THERE TIME MARK?
	je @F			       ;IF NOT, SKIP
	mov BX,RedrawAddress	       ;OTHERWISE STORE THE TIME
	mov TaddR,BX		       ;INFORMATION
	mov ax,LTime
	mov TTime,ax
	mov TFLAG,01H
@@:
	test LFeatures,080H		;IS THERE A Altitude MARK?
	je @F				;IF NOT, SKIP
	mov BX,RedrawAddress		;STORE Altitude INFO
	mov HaddR,BX
	mov AL,LAltitude
	mov TAltitude,AL
	mov HFLAG,01H
@@:
	test LFeatures,02H	       ;IS THERE ANNOTATION?
	je NRANNO		       ;
	call STANNO		       ;IS SO STORE IT IN THE BUFFER
NRANNO:
	;now see if there is nav data
	test LFeatures,08h
	je nonavdt
	test TNavFlag,1	       ;already some waiting?
	jne nonavdt		;don't overwrite
	mov di,offset TNavBuffer       ;temp buffer for redraw
	call UnCompress

	test DisplayFlags,4		;is any nav data visible?
	je DontStoreNav
	test DisplayFlags,10h		;is position data only on?
	jne @f				;if not, store all
	mov di,offset TNavBuffer
	call ValidNavString
	jc DontStoreNav
@@:
	;store it
	mov BX,RedrawAddress		       ;store the address
	mov naddr,BX
	mov TNavFlag,1		       ;flag 'nav data waiting'
DontStoreNav:
	;NOW SEE IF THERE IS ANNOTATION TO BE PRINTED
nonavdt:
	mov AL,BTAIL
	cmp AL,BHEAD
	jz NPANNO		       ;IF THE BUFFER IS EMPTY, SKIP
	mov AH,0
	shl AX,4
	mov SI,offset RedrawAnBuffer
	add SI,AX
	mov BX,[SI]		       ;GET addR OF FIRST ANNOTATION IN SI
	add BX,0500H
	cmp BX,RedrawAddress		       ;IF IT IS 10
	ja NPAnno
	add BX,0500H		       ;or 11 LINES UP, PRINT IT
	cmp BX,RedrawAddress
	Jb NPAnno
DRANNO:
	mov BX,[SI]
	add SI,3
	mov CL,12
	mov DI,offset LAnnotation
@@:
	mov AL,[SI]		       ;COPY THE ANNOTATION TEXT TO
	mov [DI],AL		       ;BE PRINTED
	inc SI
	inc DI
	dec CL
	jnz @b
	test DisplayFlags,01H
	je @f
	call PANNO		       ;PRINT IT
@@:
	mov AL,BTAIL
	inc AL
	and AL,07H
	mov BTAIL,AL
NPANNO:
	test TFLAG,1		       ;IS THERE A MINUTE MARK WAITING?
	je NPTIME
	mov bx,RedrawAddress
	sub bx,0500h
	sub bx,taddr
	js NPTime
	mov TFLAG,0
	mov ax,TTime
	call EXTIME
	mov BX,TaddR
	add BX,76
	mov SI,offset ETBUFF
	call FIXAN

NPTIME:
	test HFLAG,01H		       ;IS THERE A Altitude FLAG WAITING?
	je NPHGHT
	mov bx,RedrawAddress
	sub bx,0500h
	sub bx,haddr
	js NPHGHT
	mov HFLAG,00H		       ;CLEAR FLAG
	test DisplayFlags,02H	       ;test CONTROL
	je NPHGHT
	mov AL,TAltitude		       ;Altitude IN AL
	mov AH,0
	shl ax,1		       ;if so, double altitude
	mov BL,25
	shl AX,1
	DIV BL
	aam			       ;split into tens and units
	add ax,3030h
	mov SI,offset LAnnotation
	cmp ah,'0'		       ;is first digit zero
	jne @f
	mov ah,' '		       ;if so, replace with a space
@@:
	mov [SI],AH
	mov [SI+1],AL
	mov byte PTR [SI+2],'m'	       ;print 'xxm'
	mov byte PTR [SI+3],0FFH
	mov LAnPosition,80		       ;CENTRE OF SCREEN
	mov BX,HaddR
	call PANNO		       ;PRINT Altitude MARK

NPHGHT:
	test TNavFlag,1 	       ;is there a nav string waiting
	je npnavm
	mov bx,RedrawAddress
	sub bx,500h
	sub bx,naddr
	js NPNavM

	mov si,offset TNavBuffer
	mov bx,naddr
	call fixan
	mov TNavFlag,0
npnavm:
	test VFLAG,01H		       ;IS THERE A EVENT NUMBER WAITING?
	je NPEVEN
	mov bx,RedrawAddress
	sub bx,0500h
	sub bx,Vaddr
	js NPEven
	mov VFLAG,00H		       ;CLEAR FLAG
	mov ax,TVNumber		       ;GET EVENT MARK NUMBER
	mov SI,offset LAnnotation	;build text in 'LAnnotation'
	mov bx,ax
	and ax,0f0fh
	and bx,0f0f0h
	shr bx,4
	add ax,3030h
	add bx,3030h
	xchg al,bh
	mov [si],ax
	mov [si+2],bx
	mov byte PTR [SI+4],0FFH       ;STRING TERMINATOR
	mov BX,VaddR
	call PRANN2		       ;PRINT EVENT NUMBER
NPEVEN:
	mov ah,80		       ;adjust RedrawAddress
	mov al,ScrollDrop	       ;80 bytes per line
	mul ah
	add RedrawAddress,ax

	mov AX,RLINE		       ;DECREASE RLINE
	SUB AX,1
	and ax,BufferLimit
	mov RLINE,AX
	clc			       ;carry clear if line was printed
	RET


RTERM:	;this terminates the redraw process
	cmp FreezeMode,0
	je @f
	call DoubleLine
@@:
	and NewCurZoom,1
	and InitRedraw,0FDH	       ;SIGNAL REDRAW FINISHED
	mov LookBackScrl,0
	mov HideMouse,0
	call PrintArrow		       ;draw arrow
	mov al,SnapshotPending
	test al,0c0h
	jne @f
	ret
@@:
	test al,80h
	je DoBitmap
	call ComenceHPDump
	mov SnapshotPending,0
	ret

DoBitmap:
	IF FORCEEXPORT
	mov di,offset BitmapExprtMsg	;'Exporting'
	call petext
	mov BitmapError,0
	call ExportBitmap
	mov al,BaudRate
	call SetUartBaud
	mov al,BitmapError	       ;any error?
	cmp al,0
	jne TimeOutError
	mov si,offset DumpDoneMsg
	call PrintErrorMsg
	ret
TimeOutError:
	mov si,offset ErrorMsg31	;'comms error'
	call Rebuke
	ret

	ELSE

	;test LastWasCalcPos,1
	;je @f
	jmp @f
	;write the fixes in the message and annotation boxes
	mov ebx,LatitudeFix
	mov si,offset InfoMessage
	mov ch,0
	call WriteNavMinutes
	mov al,LightStatText
	mov TextColour,al
	call scrnad
	add bx,618
	mov si,offset InfoMessage
	mov ch,060h
	call ForceLength

	mov ebx,LongitudeFix
	mov si,offset InfoMessage
	mov ch,1
	call WriteNavMinutes
	call pitext
	jmp Bacon
@@:
	mov di,offset BitmapWriteMsg	;'Writing'
	call petext
Bacon:
	call SwitchToRealMode
	call SaveBitmap
	call SwitchToProtMode
	mov al,BitmapError	       ;any error?
	cmp al,0
	jne FNameError
	mov si,offset DumpDoneMsg
	call PrintErrorMsg
	ret
FNameError:
	mov si,offset ErrorMsg30
	call Rebuke
	ret
	ENDIF

WriteSoftUpdate:
	IF DOS
	call rsense
	call VerifyForRead		       ;CHECK disk IS IN
	jnc @f
	mov si,offset ErrorMsg7        ;'no disk'
	call Rebuke		       ;Rebuke IF NOT
	jmp KeyDone
@@:
	;load directory
	call LDirS
	mov si,offset DirSec
	;check if record 1 is a software update
	cmp byte ptr [si],03h
	je @f
	mov si,offset ErrorMsg42	;no update
	call Rebuke
	jmp KeyDone

@@:
	mov ax,[si+28]			;get length
	mov UpdateLength,ax
	mov di,offset BitmapWriteMsg	;'Writing'
	call petext
	;load program from MO disk
	;use pseg for transfer
	call ReadNewSoft
	call SwitchToRealMode
	;save file to hard disk
	mov ah,3ch
	mov cx,0
	mov dx,offset UpdateName
	int 21h
	mov FileHandle,ax
	mov bx,ax
	mov cx,UpdateLength
	mov dx,0
	push ds
	mov ax,pseg
	mov ds,ax
	mov ah,40h
	int 21h
	pop ds
	mov ah,3eh
	mov bx,FileHandle
	int 21h
	call SwitchToProtMode
	mov si,offset DumpDoneMsg
	call PrintErrorMsg
	jmp KeyDone
	ENDIF

STANNO:
	movzx si,BHEAD
	shl si,4
	add si,offset RedrawAnBuffer
	mov BX,RedrawAddress
	mov [SI],BX
	add SI,3
	mov CL,12
	mov DI,offset LAnnotation
@@:
	mov AL,[DI]
	mov [SI],AL
	inc SI
	inc DI
	dec CL
	jnz @b
	mov AL,BHEAD
	inc AL
	and AL,07H
	mov BHEAD,AL
	RET

ScaleAltitude: ;this scales the Altitude for map mode
	mov ax,GS:[0f83H]	       ;get range in ah
	xchg al,ah		       ;and Altitude in al
	and ah,0fh		       ;range	scale
	mov BL,120
	cmp AH,0		       ;50m	6
	je scaler
	mov BL,60
	cmp AH,1		       ;100m	3
	je scaler
	mov BL,48
	cmp ah,2		       ;125m	2.4
	je scaler
	mov bl,40
	cmp ah,3		       ;150m	2
	je scaler
	mov bl,30
	cmp ah,4		       ;200m	1.5
	je scaler
	mov bl,20
	cmp ah,5		       ;300m	1
	je scaler
	mov bl,15
	cmp ah,6		       ;400m	0.75
	je scaler
	mov bl,80
	cmp ah,7		       ;75m	4
	je scaler

scaler:
	mov ah,0
	mul bl
	xor dx,dx
	mov bx,20
	div bx
	ret


StorePrintLine:
	;THIS STORES THE LINE 'OLINE' TO THE PRINTER BUFFER
	;FROM THE MAIN BUFFER
	;IT IS GEOMETRICALLY CORRECTED and ALL
	;ANNOTATION, TIME MARKS, EVENT MARKS and Altitude MARKS
	;ARE addED
	;call IF OLINE<>DLINE
	;the buffer is 32 lines each holding 4096 bytes
	;all printers use this

	assume es:pseg

	mov ax,030h
	push es
	mov es,ax		       ;printer buffer segment
	mov AX,OLINE		       ;GET source SCREEN LINE
	shl AX,3
	add AX,038H		       ;GET CORRESPONDING SEGMENT
	mov GS,AX		       ;in gs
	;get some values from the scan line
	mov ax,gs:[0f80h]		;time (hours & minutes)
	mov LTime,ax
	mov ax,gs:[0f83h]		;range
	mov LRange,al
	mov LAltitude,ah		;altitude
	mov ax,gs:[0f8eh]
	mov LVNumber,ax 		;event mark number
	mov al,gs:[0f8ch]
	mov LSpeed,al			;speed
	mov eax,gs:[0f90h]
	mov si,offset LAnnotation	;annotation text and position
	mov eax,gs:[0f90h]
	mov [si],eax
	mov eax,gs:[0f94h]
	mov [si+4],eax
	mov eax,gs:[0f98h]
	mov [si+8],eax
	mov al,gs:[0f8dh]
	mov LFeatures,al
	;now work the repitition factor 'prept'
	movzx bx,Lspeed		       ;get speed in bx
	cmp SnapNumber,00h
	jne @f
	cmp PrinterNumber,1	       ;deskjet?
	je @f
	cmp PrinterNumber,6	       ;3710?
	je @f
	test ScreenGeometry,2
	jne @f			       ;jump if in map mode
	mov Prept,1
	jmp Prntl2
@@:
	;double it if PrinterMode is 1,2 or 3 to get x2
	;along-track zoom
	cmp PrinterMode,0	       ;jump ahead if PrinterMode=0
	je @f
	shl bx,1		       ;otherwise double the speed
@@:
	mov ax,CompressionFactor       ;factor for compression
	test DeskJetDPI,0
	je @f
	shl ax,1
@@:
	mul bx
	add ax,PrinterRemain
	mov PrinterRemain,ax
	jnc @f
	inc dl
@@:
	mov Prept,dl

PRNTL2:
	movzx edi,ohead		       ;find the address of the
	shl edi,12		       ;pointer in the printer buffer
	mov PBufAd,edi		       ;store it
	;first expand line into 4096 byte buffer
	cld
	;RAW MODE COMPRESSION IS 3840>4096 (15>16)
	mov cx,256
	xor si,si
	movsx ebx,InvPal
@@:
	lodsd gs:[si]
	xor eax,ebx
	stosd es:[edi]

	lodsd gs:[si]
	xor eax,ebx
	stosd es:[edi]

	lodsd gs:[si]
	xor eax,ebx
	stosd es:[edi]

	lodsd gs:[si]
	xor eax,ebx
	stosd es:[edi]
	dec si
	loop @b
	cmp ScreenGeometry,00H	       ;CHECK For SRC MODE
	je PRNEND		       ;jump if not
	;slant range correct the buffer
	call ScaleAltitude	       ;skip water columb
	;buffer is now 4096, not 3840 so adjust water columb size
	shl ax,4		       ;multiply by 16 then divide by 15
	xor dx,dx
	mov bx,15
	div bx
	add ax,21		       ;skip over ring
	movzx esi,AX		       ;SI=SOURCE POINTER
	shl AX,2		       ;dword pointer
	mov bx,ax
	mov eax,SquaresTable[bx]
	mov AltitudeSquared,EAX	       ;AltitudeSquared=(SCALED Altitude)^2
	xor edx,edx		       ;DESTINATION COUNT
	mov CH,0		       ;INITIALIZE REPEAT LIMIT COUNTER

	mov ebx,PBufAd
	;add ebx,2048

PMAP2:
	mov al,es:[ebx+esi+2048]       ;al=stbd value
	xor esi,07ffh
	mov ah,es:[ebx+esi]	       ;ah=port value
	xor esi,07ffh
	mov edi,edx
	mov es:[ebx+edi+2048],al
	xor edi,07ffh
	mov es:[ebx+edi],ah

	inc CH			       ;INCREASE REPEAT COUNTER
	cmp CH,10		       ;CHECK REPEAT LIMIT
	jz @F			       ;IF EXCEEDED, INCREASE SOURCE

	mov edi,edx

	mov EAX,SquaresTable[edi*4]	;EAX=DESTINATION SQUARED
	add EAX,AltitudeSquared

	mov edi,esi		       ;source count
	cmp EAX,SquaresTable[edi*4]	;eax>di^2?
	jb PMAP1
@@:
	mov CH,0		       ;RESET REPEAT LIMIT COUNTER
	inc esi			       ;INCREASE SOURCE POINTER
PMAP1:
	inc edx
	cmp esi,2048		       ;FINISH WHEN SOURCE=2048
	jb PMAP2
	cmp edx,2048
	jae PMAP3

	mov edi,pbufad		       ;NOW FILL IN THE REMAINING
	add edi,2048
	lea esi,[edi-1]
	add edi,edx		       ;DI=RIGHT
	SUB esi,edx		       ;SI=LEFT
	mov AL,00H		       ;AL=COLOUR
@@:
	stosb es:[edi]
	mov es:[esi],AL
	;MOVE THE POINTERS
	dec esi
	inc edx			       ;INCREASE THE COUNT
	cmp edx,2048
	jne  @B
PMAP3:
	;src correction now on
PRNEND:
	;NOW add RANGE LINES IF ON
	test DisplayFlags,40h
	je PRNTL6
	mov edi,PBufAd
	add edi,408
	mov cl,9
	mov ax,0ffffh
@@:
	stosw es:[edi]
	add edi,406
	dec cl
	jnz @B
PRNTL6:
	;add altitude trace
	cmp ScreenGeometry,00H		;CHECK For SRC MODE
	jne @f				;jump if so
	inc PTraceColour
	test PTraceColour,8
	je @f
	call ScaleAltitude
	cwd
	shl ax,4
	mov bx,15
	div bx
	movzx ebx,ax
	mov edi,PBufAd
	mov dword ptr es:[edi+ebx+2048],0ffffffffh
	sub edi,ebx
	dec edi
	mov dword ptr es:[edi+2048],0ffffffffh
@@:
	mov AL,OHEAD		       ;increase head pointer, wrapping
	inc AL			       ;round if needed
	and al,01fh
	mov OHEAD,AL

	dec PREPT
	jnz PRNTL2

PRNTL5:
	;NOW OTHER FEATURES ARE addED
	test LFeatures,0cfh	       ;are ther any features?
	je prntl9

	test LFeatures,02H	       ;IS THERE ANNOTATION?
	je @F
	test DisplayFlags,01H
	je @F
	mov ebx,PBufAd
	movzx eax,LAnPosition	       ;get pixel position
	shl ax,7		       ;*128
	mov cx,5
	mov dx,0
	div cx			       ;/5=25.6*pan   (4096/160)
	add ebx,eax
	mov si,offset LAnnotation
	call FIXPAN		       ;PRINT THE ANNOTATION
@@:
	test LFeatures,08h	       ;is there nav data?
	je noprintnav
	test DisplayFlags,4	       ;is nav data on?
	je noprintnav
	;print 32 bytes of nav data from gs:[0fc0h-0fdfh]
	;first copy the string from 'oline' to NavDataString

	mov di,offset NavDataString
	push di
	call UnCompress
	pop si
	test DisplayFlags,10h		;is position data only on?
	jne @f
	cmp dword ptr NavDataString[3],',AGG'
	je @f
	cmp dword ptr NavDataString[3],',LLG'
	jne noprintnav
@@:
	mov ebx,pbufad
	IF EGS
	add ebx,2048
	ENDIF
	call fixpan		       ;print the nav data
noprintnav:

	test LFeatures,01H	       ;IS THERE AN EVENT MARK
	je PRNTL7
	test DisplayFlags,8	       ;are they on?
	je prntl7		       ;if not, jump
	cld
	mov ecx,1024		       ;print a black line
	mov edi,PBufAd		       ;with 1024 dwords
	movsx eax,InvPal
	;xor eax,eax
	rep stosd es:[edi]
	;write in the event mark number
	mov SI,offset LAnnotation
	mov ax,LVNumber
	mov bx,ax
	and ax,0f0fh
	and bx,0f0f0h
	shr bx,4
	add ax,3030h
	add bx,3030h
	xchg al,bh
	mov [si],ax
	mov [si+2],bx
	mov byte ptr [SI+4],0FFH       ;STRING TERMINATOR
	mov ebx,PBufAd		       ;GET addRESS
	cmp PrinterNumber,6		;3710?
	jne @f
	add ebx,20			;if so, shift number across a bit
@@:
	cmp PrinterMode,2	       ;if in PrinterMode 2, add 2048
	jne @F
	add ebx,2048
@@:
	call FIXPAN		       ;PRINT THE ANNOTATION

PRNTL7:
	test LFeatures,04H	       ;IS THERE A TIME MARK
	jz PRNTL8		       ;IF NOT, SKIP
	mov ax,LTime		       ;PRINT THE MINUTE MARK IF REQUIRED
	call EXTIME		       ;expand time to string
	mov ebx,PBufAd		       ;time mark goes on the right hand
	add ebx,3960		       ;side of the picture
	cmp PrinterMode,1	       ;unless left hand side mode is on
	jne @F			       ;if so, put time mark
	sub ebx,2048		       ;at the middle
@@:
	mov SI,offset ETBUFF
	call FIXPAN		       ;fix it in the buffer

PRNTL8:
	test LFeatures,080H	       ;IS THERE A Altitude MARK?
	jz PRNTL9		       ;IF NOT, SKIP
	test DisplayFlags,02H	       ;ARE THEY ACTIVE?
	jz PRNTL9		       ;IF NOT, SKIP
	mov AL,LAltitude	       ;Altitude IN AL
	mov AH,0
	shl ax,1		       ;if so, double altitude
	mov BL,25
	shl AX,1
	DIV BL
	aam
	add ax,3030h
	mov SI,offset LAnnotation
	cmp ah,'0'		       ;is first digit zero?
	jne @f
	mov ah,' '		       ;if so, replace with space
@@:
	mov [SI],AH

	mov [SI+1],AL
	mov byte PTR [SI+2],'m'	       ;print 'xxm'
	mov byte PTR [SI+3],0FFH
	mov ebx,PBufAd		       ;in the middle
	add ebx,2048
	cmp PrinterMode,1	       ;if in mode 1, move slightly to
	jne @F			       ;the left
	sub ebx,80
@@:
	call FIXPAN

PRNTL9:
	mov AX,OLINE
	inc AX
	and ax,BufferLimit
	mov OLINE,AX
	pop es

	RET

StorePrintNull:
	mov AX,OLINE
	inc AX
	and ax,BufferLimit
	mov OLINE,AX
	ret


FIXPAN: ;THIS PLACES ANNOTATION TEXT IN THE PRINTER BUFFER
	;STRING AT SI
	;BUFFER addRESS IN ebx
	;FIRST A BLACK BACKGROUND BLOCK MUST BE PRINTED
	push SI
	push ebx
	;FIRST THE LENGTH IS FOUND IN CL
	mov CL,1		       ;allow 1 pixel border
@@:
	mov AL,[SI]		       ;get character from string
	cmp AL,0FFH		       ;end of string?
	je @F			       ;jump if so
	sub al,20h		       ;ascii adjust
	mov AH,0		       ;get offset in font
	shl AX,3		       ;each character is a bytes long
	mov DI,offset FontA	       ;font is 'FontA'
	add DI,AX		       ;pointer in di
	mov AL,FS:[DI+7]	       ;x size is bits 0-2 of last byte
	and AL,07H		       ;of the character
	inc al			       ;inter-character space
	add CL,AL		       ;add to total
	inc SI			       ;advance string pointer
	JMP @B			       ;loop back
@@:
	;cl now holds the length, in pixels, of the string
	;first print a blank box
	mov AH,20		       ;20 pixels deep
	mov DL,CL		       ;save length in dl

PRNTB1:
	movzx cx,DL		       ;get length in cx
	mov edi,ebx		       ;save buffer address
@@:
	mov dword ptr es:[ebx],0h	;background colour x 4
	add ebx,4		       ;increase pointer
	LOOP @B 		       ;loop round
	mov ebx,edi		       ;restore buffer address
	sub ebx,4096		       ;next line down (down in memory)
	and ebx,1ffffh		       ;wrap round 128k
	dec AH			       ;background is 20 deep
	jnz PRNTB1		       ;loop round 20 times

	pop ebx			       ;restore buffer address
	pop SI			       ;and string pointer

	sub ebx,8192		       ;come down 2 lines
	and ebx,1ffffh		       ;wrap round 128k

	;NOW PRINT THE CHARACTERS
	add ebx,4		       ;left margin
PRNTAC:
	mov AL,[SI]		       ;GET CHARACTER
	cmp AL,0FFH		       ;STRING FINISHED?
	je PRNTAF		       ;JUMP IF SO
	sub al,20h		       ;ascii adjust
	mov AH,0		       ;TIMES BY 8
	shl AX,3
	mov DI,offset FontA	       ;CHARACTER TABLE
	add DI,AX		       ;DI IS addRESS OF FONT
	mov CH,8		       ;EIGHT ROWS
	push ebx

PRNTA5:
	mov CL,2		       ;each pixel is two bytes deep

PRNTA2:
	mov AH,FS:[DI]		       ;GET FONT LINE
	and AH,0F8H		       ;and out LENGTH

	push ebx		       ;save buffer address
	mov DL,5		       ;5=MAX WIDTH
PRNTA1:
	shl AH,1		       ;shift font line
	JNC @F			       ;if bit not set, skip
	mov dword ptr es:[ebx],0ffffffffH	       ;write 4 black dots

@@:
	add ebx,4
	dec DL			       ;next pixel
	jnz PRNTA1		       ;loop round
	pop ebx			       ;restore address

	sub ebx,4096		       ;NEXT LINE OF BUFFER
	and ebx,1ffffh		       ;wrap round 128k

	dec CL			       ;go round twice
	jnz PRNTA2		       ;each pixel is 2 deep

	inc DI			       ;NEXT LINE OF FONT
	dec CH			       ;do 8 rows
	jnz PRNTA5		       ;NEXT ROW
	pop ebx			       ;restore buffer adresss

	;CHAR NOW COMPLETE

	movzx eax,byte ptr FS:[DI-1]   ;LOOK BACK TO GET length
	and al,07H		       ;from bits 0-2 of the byte
	inc al			       ;of char and allow for spacing
	lea ebx,[ebx+eax*4]	       ;4 bytes per pixel wide
	inc SI			       ;NEXT CHAR
	JMP PRNTAC		       ;GO AGAIN
PRNTAF: RET			       ;finish

SendPrintLine8:
	;*********************
	;this is for EPC 9800 20 inch printer
	;*********************

	mov si,offset EPCMessage	;set up printer to print scan
	jmp @f				;the rest is the same as the dowty

SendPrintLine5:
	;*********************
	;this is for DOWTY 200 20 inch printer
	;*********************
	;THIS SENDS THE LAST LINE IN THE BUFFER TO THE PRINTER
	;EITHER THE FULL WIDTH, THE LEFT HALF or RIGHT HALF
	;or the centre
	;IS SENT

	mov si,offset Graph0Message    ;put printer in graphics mode
@@:

	mov ax,30h		       ;printer buffer segment
	push es
	mov es,ax
	call SendPrinterCommand	       ;full width
	jc PrintTimeOut

	movzx esi,OTAIL		       ;find offset of source line in buffer
	shl esi,12		       ;4096 x otail
	cmp PrinterMode,2	       ;if right side, add 2048
	jne @F			       ;to start at the middle
	add esi,2048
@@:
	mov CX,4096		       ;4096 pixels across

SPL5:
	mov al,es:[esi]		       ;get byte from buffer
	call SendPrinterByte
	jc PrintTimeOut

	;now the source pointer must be incremented
	;every time im PrinterMode 0
	;and every other time in PrinterModes 1 and 2
	;to achieve X2 zoom

	cmp PrinterMode,00h	       ;if PrinterMode=0, the source pointer
	je @f			       ;is always incremented
	test cl,1		       ;in PrinterModes 1, 2 and 3 it depends
	je NoIncSrc5		       ;on the state of bit 0 of CL
@@:
	inc SI			       ;inc POINTER
NoIncSrc5:
	LOOP SPL5		       ;DO 4096 PIXELS

	;LINE HAS BEEN TRANSMITTED
	pop es
	mov AL,OTAIL
	inc AL
	and al,01fh
	mov OTAIL,AL
	RET


SendPrinterByte:
	;this sends a byte to the printer port at 'LPTAddress'
	IF NULLPRINTER
	clc
	ret
	ELSE

	mov DX,LPTAddress	       ;OUTPUT PORT
	out DX,AL		       ;out data

	mov ah,PTickCount
	add ah,128
	inc dx			       ;status port
@@:				       ;wait for NOTBUSY
	cmp ah,PTickCount
	jz SendTimeOut
	IN AL,DX
	test AL,080H
	jz @B

	mov AL,6H		       ;delay
@@:
	dec AL
	jnz @B

	inc dx				;control port
	mov AL,0dH
	out DX,AL			;PULSE STROBE ON
	mov AL,6H		       ;delay
@@:
	dec AL
	jnz @B

	mov AL,0cH		       ;THEN OFF
	out DX,AL
	IF SLOWPRINT
	mov AL,6h		       ;delay
@@:
	dec AL
	jnz @B

	dec dx				;status port
	mov ah,PTickCount
	add ah,128
@@:				       ;wait for NOTBUSY
	cmp ah,PTickCount
	jz SendTimeOut
	IN AL,DX
	test AL,080H
	jz @B
	mov dx,100
@@:
	dec dx
	jnz @b
	ENDIF
	clc			       ;success
	ret

SendTimeOut:
	stc			       ;failure
	ret
	ENDIF


SendPrinterCommand:
	;this sends a string of characters starting at [si+1]
	;to the printer
	;the length is at [si]


	mov cl,fs:[si]		       ;get length byte
SendPrinter1:
	inc si
	mov al,fs:[si]		       ;get data
	call SendPrinterByte	       ;send it
	jnc @f			       ;timeout check
	ret			       ;carry set if timeout
@@:
	dec cl			       ;length count
	jnz SendPrinter1
	ret			       ;return with no carry when done

InitializePrinter:
	cmp PrinterNumber,6		;3710?
	jne @f
	mov dx,LPTAddress
	add dx,2
	mov al,0eh
	out dx,al
	ret
@@:
	cmp PrinterNumber,4	       ;Alden 9315CTP
	jne @f
	call ResetPrinter
	mov ecx,10000000
InitDel:
	loopd InitDel
	jmp InitializeAlden
@@:
	cmp PrinterNumber,1	       ;deskjet
	je @f
	clc
	ret
@@:
	mov si,offset HPBannerCodes
	call SendPrinterCommand
	ret

ResetPrinter:
	;first pulse the initialize line
	mov dx,LPTAddress
	add dx,2
	;in al,dx			;control port
	mov al,0e8h
	out dx,al
	mov cx,1000h
@@:
	nop
	loop @b
	mov al,0ech
	;or al,04h
	out dx,al
	mov cx,1000h
@@:
	nop
	loop @b

	;now see if busy is not set
	mov edi,100000h
	dec dx				;status port
@@:
	dec edi
	jz @f
	in al,dx
	shl al,1
	jc @b
	clc
	ret				;is not selected
@@:
	stc				;timeout
	ret

	;--printer port bits
	;
	;379h (inputs)
	;bit	line
	;3	-ERROR
	;4	+SELECT
	;5	+PAPER OUT
	;6	-ACKNOWLEDGE
	;7	+BUSY
	;
	;37Ah (outputs)
	;bit	line
	;0	-STROBE
	;1	+AUTO FEED
	;2	-INITIALIZE
	;3	+SELECT IN
	;4	Enable printer interrups

InitializeAlden:
	mov si,offset AldenCommand
	call SendPrinterCommand
	mov si,offset AldenTable
	call SendPrinterCommand
	ret

SendPrintLine4:
	;*********************
	;this is for Alden 9315 CTP and EPC GSP-1086
	;*********************

	;settings for GSP-1086 are:
	;LPI=200
	;KEYBOARD=DISABLED
	;DATA INPUT=PARALLEL
	;SWEEP=REVERSE
	;WIDTH=2048
	;DATA TYPE=8BIT
	;IMAGE=POSITIVE
	;REPEAT LN=1

	;THIS SENDS THE LAST LINE IN THE BUFFER TO THE PRINTER
	;EITHER THE FULL WIDTH, THE LEFT HALF or RIGHT HALF
	;IS SENT


	mov ax,30h		       ;printer buffer segment
	push es
	mov es,ax


	movzx esi,OTAIL		       ;find offset of source line in buffer
	shl esi,12		       ;4096 x otail
	add esi,4095		       ;start from far side (1086 can reverse
	;sweep but alden cannot

	cmp PrinterMode,1	       ;if left side, sub 2048
	jne @F
	sub esi,2048
@@:
	mov CX,2048		       ;9315 & 1086 is 2048 dots across

SLP4:
	mov AL,es:[esi]		       ;get byte from AL
	call SendPrinterByte
	jc PrintTimeOut
	;now the source pointer must be incremented
	;every time in PrinterMode 0
	;and every other time in PrinterModes 1, 2 and 3
	;to achieve X2 across zoom

	cmp PrinterMode,00h	       ;if PrinterMode=0, the source pointer
	jne @f			       ;is decremented twice
	dec esi 		       ;in PrinterModes 1,2 and 3 it is
@@:				       ;decremented once
	dec esi
	LOOP SLP4		       ;DO 2048 PIXELS

	;LINE HAS BEEN TRANSMITTED
	pop es
	mov AL,OTAIL
	inc AL
	and al,01fh
	mov OTAIL,AL
	RET


SendPrintLine6: ;(ultra 3710)
	;*********************
	;this is for ultra 3710 + interface unit
	;*********************
	;THIS SENDS THE LAST LINE IN THE BUFFER TO THE PRINTER
	;EITHER THE FULL WIDTH, THE LEFT HALF or RIGHT HALF
	;or the centre
	;IS SENT
	;printer settings:
	;L & R inputs=Digital
	;R Direction=-->, L=<--
	;L & R %=50%
	;paper drive=External
	;L & R trigger=External
	;L & R sweep time=20-50ms
	;L & R delay=0ms
	;L & R white=0, black=63

	mov ax,30h		       ;printer buffer segment
	push es
	mov es,ax
	;check fifo is empty
	mov dx,LPTAddress
	inc dx
	mov edi,10000000
@@:
	dec edi
	je PrintTimeOut

	in al,dx
	test al,80h
	jz @b

	;turn off trigger
	inc dx
	mov al,0eh
	out dx,al
	;advance paper
	mov al,0ch
	out dx,al
	mov cx,1000
@@:
	loop @b
	mov al,0ah
	out dx,al
	mov cx,100
@@:
	loop @b
	mov al,0eh
	out dx,al


	movzx esi,OTAIL		       ;find offset of source line in buffer
	shl esi,12		       ;4096 x otail
	add esi,2048

	cmp PrinterMode,2	       ;if right side, add 1024
	jne @f
	add esi,1024
@@:
	cmp PrinterMode,1	       ;if left side, sub 1024
	jne @f
	sub esi,1024
@@:
	mov edi,esi
	dec edi

	mov CX,2048		       ;3710 is 1750 dots each side
SPL6:
	mov AL,es:[esi]		       ;get byte from AL=0-15
	mov ah,es:[edi]
	shr ah,4
	and al,0f0h
	or al,ah
	mov dx,LPTAddress
	out dx,al			;data byte
	;pulse strobe
	add dx,2
	test cl,7
	je NoS3710
	mov al,0fh
	out dx,al
	dec al
	mov ah,1
@@:
	dec ah
	jnz @b

	out dx,al
	mov ah,1
@@:
	dec ah
	jnz @b
NoS3710:

	;now the source pointer must be incremented
	;every time im PrinterMode 0
	;and every other time in PrinterModes 1, 2 and 3
	cmp PrinterMode,00h	       ;if PrinterMode=0, the source pointer
	je @f			       ;is always incremented
	test cl,1		       ;in PrinterModes 1, 2 and 3 it depends
	je NoIncSrc6		       ;on the state of bit 0 of CL
@@:
	;to achieve X2 across zoom
	inc esi
	dec edi
NoIncSrc6:
	LOOP SPL6
	mov dx,LPTAddress
	mov al,0
	out dx,al
	add dx,2
	;pulse strobe
	;mov al,0fh
	;out dx,al
	;dec al
	;out dx,al

	;trigger the scan
	mov al,6
	out dx,al

	;LINE HAS BEEN TRANSMITTED
skipit:
	pop es
	mov AL,OTAIL
	inc AL
	and al,01fh
	mov OTAIL,AL
	RET


SendPrintLine2: ;(raytheon)
	;*********************
	;this is for RAYTHEON TDU 850
	;*********************
	;THIS SENDS THE LAST LINE IN THE BUFFER TO THE PRINTER
	;EITHER THE FULL WIDTH, THE LEFT HALF or RIGHT HALF
	;or the centre
	;IS SENT

	mov ax,30h		       ;printer buffer segment
	push es
	mov es,ax

	movzx si,OTAIL		       ;find offset of source line in buffer
	shl si,11		       ;2048 x otail

	cmp PrinterMode,2	       ;if right side, add 1024
	jne @F
	add SI,1024
@@:
	mov CX,1728		       ;tdu-850 is 1728 dots across

SPL2:
	mov AL,es:[SI]		       ;get byte from AL=0-15
	test GammaCorrection,1
	je @f
	;now apply gamma correction
	mov bx,offset PrinterGamma
	xlatb fs:PrinterGamma	       ;gamma translation
	;the data is always sents to the most significant
	;bits no matter how many grey scales are on eg
	;16 grey scales= bits 7-4
	jmp GammaDone2
@@:
	shl al,2
GammaDone2:
	shl al,2
	or AL,01H		       ;or IN EOL (inactive)
	call SendPrinterByte
	jc PrintTimeOut
	;now the source pointer must be incremented
	;every time im PrinterMode 0
	;and every other time in PrinterModes 1, 2 and 3
	;to achieve X2 across zoom

	cmp PrinterMode,00h	       ;if PrinterMode=0, the source pointer
	je @f			       ;is always incremented
	test cl,1		       ;in PrinterModes 1, 2 and 3 it depends
	je NoIncSrc2		       ;on the state of bit 0 of CL
@@:
	inc SI			       ;inc POINTER
NoIncSrc2:
	;now generate 2048>1728 compression by advancing si
	;if si mod 32=3,9,15,23,31
	mov ax,si
	and ax,31		       ;get si mod 32
	shr al,1
	jnc nodiv
	cmp al,1
	je @f
	cmp al,4
	je @f
	cmp al,7
	je @f
	cmp al,11
	je @f
	cmp al,15
	jne nodiv
@@:
	inc si
nodiv:
	LOOP SPL2		       ;DO 1728 PIXELS

	mov DX,LPTAddress	       ;THEN PULSE NEWLINE
	mov AL,00H
	out DX,AL
	mov AL,20H
@@:
	dec AL
	jnz @B
	mov AL,01H
	out DX,AL
	;LINE HAS BEEN TRANSMITTED
	pop es
SendPrintNull:
	mov AL,OTAIL
	inc AL
	and al,31
	mov OTAIL,AL
	RET


SendPrintLine9: ;
	;*********************
	;this is for Oyo GP608P
	;*********************
	;THIS SENDS THE LAST LINE IN THE BUFFER TO THE PRINTER
	;EITHER THE FULL WIDTH, THE LEFT HALF or RIGHT HALF
	;or the centre
	;IS SENT

	mov ax,30h		       ;printer buffer segment
	push es
	mov es,ax

	mov si,offset OyoCommand
	call SendPrinterCommand

	movzx si,OTAIL		       ;find offset of source line in buffer
	shl si,11		       ;2048 x otail
	add si,2047

	cmp PrinterMode,1	       ;if left side, sub 1024
	jne @F
	sub SI,1024
@@:
	mov CX,832		       ;1664 dots across in packed nibbles
	mov bl,0		       ;control for x2
OyoLab1:
	mov AL,es:[SI]		       ;get byte from AL=0-15
	mov ah,al
	shl ah,4
	cmp PrinterMode,0
	jne OyoZoom1
	;perform across track compression for full width (13/16)
	mov dx,si
	dec si
	and dl,0fh		       ;if si mod 16
	jz DoubleIncSI1 	       ;is 0, 5 or 10, skip a byte
	cmp dl,5		       ;to give a 13/16ths reduction
	je DoubleIncSI1 	       ;ie 1664 out of 2048
	cmp dl,10
	jne @f
DoubleIncSI1:
	dec si
@@:
	jmp @f

OyoZoom1:
	;perform across track compression for port or stbd (13/8)
	;dont increase si if bl=0,2,5,7 or 10
	inc bl
	cmp bl,13
	jne Not131
	mov bl,0
Not131:
	cmp bl,0
	jz @f
	cmp bl,2
	je @f
	cmp bl,5
	je @f
	cmp bl,7
	je @f
	cmp bl,10
	je @f
	dec si
@@:
	mov AL,es:[SI]		       ;get byte from AL=0-15
	or al,ah
	cmp PrinterMode,0
	jne OyoZoom2
	;perform across track compression for full width (13/16)
	mov dx,si
	dec si
	and dl,0fh		       ;if si mod 16
	jz DoubleIncSI2 	       ;is 0, 5 or 10, skip a byte
	cmp dl,5		       ;to give a 13/16ths reduction
	je DoubleIncSI2 	       ;ie 1664 out of 2048
	cmp dl,10
	jne @f
DoubleIncSI2:
	dec si
@@:
	jmp @f

OyoZoom2:
	;perform across track compression for port or stbd (13/8)
	;dont increase si if bl=0,2,5,7 or 10
	inc bl
	cmp bl,13
	jne Not132
	mov bl,0
Not132:
	cmp bl,0
	jz @f
	cmp bl,2
	je @f
	cmp bl,5
	je @f
	cmp bl,7
	je @f
	cmp bl,10
	je @f
	dec si
@@:
	call SendPrinterByte
	jc PrintTimeOut
	;now the source pointer must be incremented
	;every time im PrinterMode 0
	;and every other time in PrinterModes 1, 2 and 3
	;to achieve X2 across zoom
	dec cx
	jnz OyoLab1		       ;DO 1728 PIXELS

	;LINE HAS BEEN TRANSMITTED
	mov AL,OTAIL
	inc AL
	and al,31
	mov OTAIL,AL
	pop es
	RET

HPTimeOut:
	pop es
	jmp @f

PrintTimeOut:
	;turn the printer off and print error message
	pop es			       ;restore video segment
	mov pausef,1		       ;pause mode on
	call StatusMode		       ;show 'pause' mode
@@:
	mov PrinterMode,00H	       ;reset mode to full width
	mov PFLAG,00H		       ;printer OFF
	call StatusPrntMode
	mov ohead,0		       ;flush printer buffer
	mov otail,0
	mov si,offset ErrorMsg25       ;'No printer'
	call Rebuke		       ;Rebuke and error message
	stc
	ret

HPScreenDump:
	mov ch,80h
	jmp @f
HPDumpLeft:
	mov ch,81h
	jmp @f
HPDumpRight:
	mov ch,82h
@@:
	cmp PFlag,0			;printer already on?
	jne PConflict
	cmp SonarIsOn,1 		;live or record mode?
	je SnapshotError
	;get repeat from anbuff
	mov si,offset anbuff
	call GetDecimal
	jc SValueError
	;count in dx
	cmp dx,250
	ja SnapCountError
	jmp @f
SValueError:
	cmp cl,0
	jne SnapCountError
	mov dl,1
@@:
	mov SnapCount,dl
	mov SnapshotPending,ch
	mov LastKeyCode,0
	jmp prmcel

PConflict:
	mov si,offset ErrorMsg34
@@:
	call Rebuke
	jmp prmcel

SnapshotError:
	mov si,offset ErrorMsg15	;'wrong mode'
	jmp @b

SnapCountError:
	mov si,offset ErrorMsg12	;'Invalid number'
	jmp @b

ComenceHPDump:
	;this sends a dump of the screen image to the current printer
	mov BannerCount,0
	mov al,SnapshotPending
	and al,3
	mov SnapshotPending,0
	mov ah,PrinterMode	       ;temporarily replace PrinterMode
	mov TempPrintMode,ah
	mov PrinterMode,al
	mov SnapNumber,1
SnapLoop:
	mov di,offset InfoMessage
	mov Dword ptr [di],'nirP'
	mov Dword ptr [di+4],'gnit'
	mov byte ptr [di+8],' '
	add di,9
	mov ah,0
	mov al,SnapNumber
	cmp al,100
	jb @f
	sub al,100
	inc ah
	cmp al,100
	jb @f
	sub al,100
	inc ah
@@:
	cmp ah,0
	je @f
	add ah,'0'
	mov [di],ah
	inc di
@@:
	aam
	cmp ah,0
	je @f
	add ah,'0'
	mov [di],ah
	inc di
@@:
	add al,'0'
	mov [di],al
	mov byte ptr [di+1],0ffh
	call pitext
	push es
	mov bp,30h		       ;point es to printer buffer
	mov es,bp
	;if the printer is a deskjet, print record info
	;and send setup codes
	cmp PrinterNumber,1	       ;DeskJet?
	jne NotDeskJet
	call PrintConfig
	jc HPTimeOut
	mov HPLineCount,2800	       ;print no more than 2800 lines
	mov si,offset HPColorCodes
	test DisplayFlags,80h	       ;false colour?
	jne @f
	mov si,offset HPMono300Codes
	test DeskJetDPI,0
	je @f
	mov si,offset HPMono600Codes
@@:
	call SendPrinterCommand	       ;prepare printer for graphics
	jc HPTimeOut
NotDeskJet:
	;if the printer is an Alden 9315, sent setup
	cmp PrinterNumber,4	       ;Alden 9315?
	jne @f
	call InitializePrinter
	jc HPTimeOut
@@:
	;now print the picture
	mov ax,ScreenLineMap[850]	;first line is from the bottom of
	mov oline,ax		       ;the screen
	;now form the palette bar in the buffer
	xor si,si
	mov cx,36864
@@:
	mov ax,si
	shr ax,6
	and al,0fh
	mov es:[si],al
	inc si
	loop @b
	xor si,si
	mov cl,20
	xor ax,ax
@@:
	mov es:[si+1022],ax
	mov es:[si+2046],ax
	add si,2048
	dec cl
	jnz @b
	xor si,si
	mov ax,si
	mov cx,1024
@@:
	mov es:[si],ax
	mov es:[si+34816],ax
	inc si
	inc si
	loop @b
	mov ohead,0		       ;reset buffer pointers
	mov otail,0
HPScreen1:
	call StorePrintLine	       ;store line in the buffer
HPScreen2:
	mov AL,OHEAD		       ;first see is otail>ohead
	cmp AL,OTAIL		       ;if so, add 32 to ohead value
	jae @f
	add al,32
@@:
	sub al,otail		       ;if the gap between ohead and
	cmp al,20		       ;otail>20 then print the line
	jbe @f
	call [PrinterDriver]	       ;call the selected driver
	jc HPTimeOut
	JMP HPScreen2
@@:
	dec HPLineCount
	jz @f
	call GETKEY
	cmp AL,03CH		       ;stop key pressed?
	je AbortHPDump
	mov AX,OLINE
	cmp ax,dline
	jne HPScreen1
	pop es
	inc SnapNumber
	dec SnapCount
	jnz SnapLoop
	;call SoundChime
	mov si,offset DumpDoneMsg
	call PrintErrorMsg
	jmp @f

AbortHPDump:
	pop es			       ;restore video segment
	mov si,offset ErrorMsg27
	call Rebuke

@@:
	;if printer is a deskjet, eject page
	cmp PrinterNumber,1
	jne @f
	mov si,offset HPEjectCodes
	call SendPrinterCommand	       ;eject page
	jc HPTimeOut
@@:
	mov al,TempPrintMode	       ;restore PrinterMode
	mov PrinterMode,al
	ret

PrintConfig:
	;the configuration text on an HP dump
	;set it up in the buffer 'HPConfigText'
	mov si,offset HPConfigMsg
	mov di,offset HPConfigText
	mov bx,di
	mov cl,64
@@:
	mov al,fs:[si]
	mov [di],al
	inc di
	inc si
	dec cl
	jnz @b
	mov ax,'FL'
	Test RangeNumber,80h	       ;LF fish?
	jne @f
	mov ax,'FH'
@@:
	mov [bx+42],ax
	MOV di,OFFSET DeskJetRanges
	MOV AL,RangeNumber	       ;message pointer is range x 4
	and al,0fh
	SHL AL,2
	mov ah,0
	ADD di,AX
	Test RangeNumber,80h	       ;LF ranges are 20 bytes more
	je @f
	add di,20
@@:
	mov eax,fs:[di]
	mov [bx+25],eax
	;put date in here
	mov di,bx
	MOV AL,Curply		       ;get number of record to be printed
	MOV AH,0		       ;find its offset in the directory
	SHL AX,5		       ;each record is 32 bytes
	MOV SI,OFFSET DIRSEC
	ADD SI,AX
	add si,13		       ;SI=START OF RECORD
	mov al,[si]
	cmp al,0
	je NoHPDate
	MOV CH,AL
	SHR AL,4		       ;FIRST DIGIT of day
	add al,30h
	cmp al,'0'		       ;blank out leading zeros
	jne @f
	mov al,' '
@@:
	mov [di+9],al
	AND ch,0FH
	add ch,30h
	mov [di+10],ch		       ;second digit
	;next comes month
	INC SI			       ;point to month
	MOV bl,[SI]		       ;GET MONTH
	;the month is printed in a three letter abbreviation eg 'Jan'
	;it is stored in bcd format
	cmp bl,9		       ;first convert to binary fromat
	jbe @f
	sub bl,6
@@:
	dec bl
	mov bh,0
	shl bx,2		       ;dword pointer
	mov eax,dword ptr fs:MonthNames[bx]
	sub eax,0202000h
	mov [di+11],eax
	;next comes year
	INC SI			       ;point to year
	MOV AL,[SI]		       ;GET year
	MOV CH,AL
	SHR AL,4
	add al,30h
	mov [di+14],al		       ;store first digit
	AND ch,0FH
	add ch,30h
	mov [di+15],ch		       ;store second digit
NoHPDate:
	mov si,offset HPTextCodes
	call SendPrinterCommand
	jnc @f
	ret
@@:
	mov ch,8		       ;8 rows
	mov ah,0
HPText1:
	mov si,offset HPMessage1       ;send 64 bytes (512 pixels)
	call SendPrinterCommand
	jnc @f
	ret
@@:
	mov si,offset HPConfigText+63
	mov cl,64
HPText2:
	movzx di,byte ptr [si]	       ;get character
	sub di,32		       ;ascii compensate
	shl di,3		       ;8 bytes per char
	mov al,8
	sub al,ch
	movzx bx,al		       ;add row count
	mov al,[di+bx+FontB]	       ;get byte from font
	call SendPrinterByte	       ;send it to printer
	jnc @f
	ret
@@:
	dec si
	dec cl
	jnz HPText2
	inc ah
	dec ch
	jnz HPText1
	clc
	ret



SendPrintLine1:
	;*******************************
	;this is for HP DeskJet/LaserJet
	;*******************************
	mov ax,30h		       ;printer buffer segment
	push es
	mov es,ax
	;routines are different for colour and grey scale
	test DisplayFlags,80h	       ;grey scale?
	je SendMonoLine
	;colour print
	mov bh,1		       ;point to first plane
SHPline3:
	mov si,offset HPMessage2       ;prepare to send 256 bytes
	cmp bh,4		       ;last plane?
	jne @f
	mov si,offset HPMessage3       ;last row of colour plane
@@:
	call SendPrinterCommand        ;(2048 pixels)
	jnc @f
	pop es
	ret
@@:
	movzx esi,OTAIL		       ;find offset of source line in buffer
	shl esi,12		       ;2048 x otail
	add esi,4095
	cmp PrinterMode,1	       ;if left side, subtract 1024
	jne @F
	sub esi,2048
@@:
	mov ch,0		       ;256 byte to each row
SHPLine2:
	mov bl,8
	mov al,0
SHPLine1:
	mov ah,es:[esi]		       ;get byte from buffer
	shr ah,4		       ;value in ah
	;for each value in in ah there are values for R, G amd B
	movzx di,ah
	cmp bh,2
	jne @f
	add di,16
@@:
	cmp bh,4
	jne @f
	add di,32
@@:
	mov ah,PrinterColours[di]	;get value for primary colour
	mov cl,bl
	and cl,03h
	shl cl,2
	movzx di,ah
	and di,0fh
	shl di,1
	mov dx,DitherPattern[di]
	mov ah,otail
	and ah,03h
	or cl,ah
	shl dx,cl
	and dh,80h
	or al,dh
	;the byte sent to the printer is built up in al
	rol al,1
	dec esi
	cmp PrinterMode,00h	       ;if PrinterMode=0, the source pointer
	jne @f			       ;is always decremented twice
	dec esi
@@:
	dec bl
	jnz SHPLine1
	;byte is in al
	call SendPrinterByte
	jnc @f
	pop es
	ret
@@:
	dec ch
	jnz SHPLine2		       ;send 256 bytes
	shl bh,1		       ;shift plane counter
	cmp bh,8		       ;do 3 planes
	jne SHPLine3
	;LINE HAS BEEN TRANSMITTED
	mov AL,OTAIL
	inc AL
	and al,31
	mov OTAIL,AL
	clc
	pop es
	RET

SendMonoLine:
	mov si,offset HPMessage3       ;1 plane=2048 pixels at 300 DPI
	test DeskJetDPI,0
	je @f
	mov si,offset HPMessage5       ;1 plane=4096 pixels at 600 DPI
@@:
	call SendPrinterCommand
	jnc @f
	pop es
	ret
@@:
	movzx esi,otail			;find offset of source line in buffer
	shl esi,12			;4096 x otail
	add esi,4095
	cmp PrinterMode,1	       ;if left side, subtract 2048
	jne @F
	sub esi,2048
@@:
	mov bp,256		       ;256 byte to each row at 300 DPI
	test DeskJetDPI,0
	je SHMLine2
	mov bp,512		       ;512 at 600 DPI
SHMLine2:
	mov bl,8		       ;8 bits to each byte
	mov al,0
SHMLine1:
	mov ah,es:[esi]		       ;get byte from buffer
	shr ah,4
	;the byte sent to the printer is built up in al
	mov cl,bl
	and cl,03h
	shl cl,2
	movzx di,ah
	and di,0fh
	shl di,1
	mov dx,DitherPattern[di]
	mov ah,otail
	and ah,03h
	or cl,ah
	shl dx,cl
	and dh,80h
	or al,dh
	rol al,1
	test DeskJetDPI,0
	jne @f				;jump if DPI=600
	dec esi
@@:
	cmp PrinterMode,00h	       ;if PrinterMode=0, the source pointer
	jne @f			       ;is always incremented by 2
	dec esi
@@:
	dec bl
	jnz SHMLine1
	;byte is in al
	call SendPrinterByte
	jnc @f
	pop es
	ret
@@:
	dec ch
	jnz SHMLine2		       ;send 256 bytes
	mov ax,BannerCount
	inc ax
	cmp ax,3290
	mov BannerCount,ax
	jb @f
	mov si,offset HPMessage6
	call SendPrinterCommand
	mov BannerCount,0
@@:
	;LINE HAS BEEN TRANSMITTED
	mov AL,OTAIL
	inc AL
	and al,01fh
	mov OTAIL,AL
	clc
	pop es
	RET


LogPosition:
	;this does as CalcNavFix but instead of displaying the
	;position, it writes it to a file
	mov LogMode,1
	jmp @f

CalcNavFix:
	;this calculates the position of the arrow using nav data
	;from an external source
	;first find the two nearest GLL nav fixes
	;or Northing/Easting fixes
	mov LogMode,0		       ;0=display, 1=log to file
@@:
	mov bx,MouseYCoord	       ;get y co-ordinate
	shl bx,1
	mov ax,ScreenLineMap[bx]
	;ax now holds the buffer line that the arrow is on
	cmp ax,BufferLimit
	jbe @f
	mov si,offset ErrorMsg26
	call Rebuke
	jmp KeyDone
@@:
	;now find the nav fixes above and below it
	mov CursorLine,ax
	mov cx,ax
FindUpperFix:
	inc cx			       ;move up
	and cx,BufferLimit	       ;wrap round
	cmp cx,cline		       ;hit the top?
	je TopOfScreen
	mov ax,cx
	shl ax,3
	add ax,38h
	mov gs,ax
	test byte ptr gs:[0f8dh],08h   ;any nav data?
	jnz @f			       ;found
	jmp FindUpperFix
@@:
	;see if it is a valid nav message
	mov di,offset UpperFixBuffer
	call UnCompress
	mov di,offset UpperFixBuffer   ;check if string is valid UTM message
	call ValidNavString
	jc FindUpperFix		       ;loop back if not
	mov FixType,al		       ;store the string type

	mov UpperLine,cx	       ;store it the location
	mov cx,CursorLine
FindLowerFix:
	dec cx			       ;move down
	and cx,BufferLimit	       ;wrap round
	cmp cx,cline		       ;hit the top?
	je TopOfScreen		       ;error
	mov ax,cx
	shl ax,3
	add ax,38h
	mov gs,ax
	test byte ptr gs:[0f8dh],08h   ;any nav data?
	jnz @f			       ;found
	jmp FindLowerFix
@@:
	;see if it is a valid nav message
	mov di,offset LowerFixBuffer
	call UnCompress
	mov di,offset LowerFixBuffer
	call ValidNavString
	jc FindLowerFix
	cmp al,FixType
	jne FindLowerFix
LowerFixFound:
	mov LowerLine,cx	       ;store it
	;now get values from string
	cmp FixType,2
	jb GetLatLong			;jump if message is GLL or GGA
	cmp FixType,3
	je GetKARTFix			;jump if message is KART
	;get UTM fixes
	mov di,offset LowerFixBuffer
	call GetXFix
	mov NavEastings2,edx
	mov di,offset LowerFixBuffer
	call GetYFix
	mov NavNorthings2,edx
	mov di,offset UpperFixBuffer
	call GetXFix
	mov NavEastings1,edx
	mov di,offset UpperFixBuffer
	call GetYFix
	mov NavNorthings1,edx
	jmp TigTog

GetKARTFix:
	mov di,(offset LowerFixBuffer+6)
	xor edx,edx
	mov bh,0
	call GetEDXLoop
	mov NavEastings2,edx
	mov di,(offset LowerFixBuffer+18)
	xor edx,edx
	mov bh,0
	call GetEDXLoop
	mov NavNorthings2,edx
	mov di,(offset UpperFixBuffer+6)
	xor edx,edx
	mov bh,0
	call GetEDXLoop
	mov NavEastings1,edx
	mov di,(offset UpperFixBuffer+18)
	xor edx,edx
	mov bh,0
	call GetEDXLoop
	mov NavNorthings1,edx
	jmp TigTog


GetLatLong:
	;extract the northings and eastings from
	;the nav data strings '$GPGLL,DDMM.MMM,N,DDDMM.MMM,E'
	mov si,offset LowerFixBuffer
	mov cl,1
	cmp FixType,1			;GGA?
	jne @f
	inc cl
@@:
	call FindParameter		;get northing
	jc InvNavMsg
	call GetNavMinutes		;convert to minutes
	mov NavNorthings2,ebx
	mov si,offset LowerFixBuffer
	mov cl,3
	cmp FixType,1			;GGA?
	jne @f
	inc cl
@@:
	call FindParameter		;get northing
	jc InvNavMsg
	call GetNavMinutes		;convert to minutes
	mov NavEastings2,ebx
	mov ax,UpperLine
	shl ax,3
	add ax,38h
	mov gs,ax
	mov si,offset UpperFixBuffer
	mov cl,1
	cmp FixType,1			;GGA?
	jne @f
	inc cl
@@:
	call FindParameter
	jc InvNavMsg
	call GetNavMinutes
	mov NavNorthings1,ebx
	mov si,offset UpperFixBuffer
	mov cl,3
	cmp FixType,1			;GGA?
	jne @f
	inc cl
@@:
	call FindParameter
	jc InvNavMsg
	call GetNavMinutes
	mov NavEastings1,ebx
TigTog:
	;now get layback and angle from the cursor line
	mov ax,CursorLine
	shl ax,3
	add ax,38h
	mov gs,ax
	mov ax,NavLayback
	mov CursorLayback,ax
	mov ah,gs:[0f87h]
	mov CursorAngle,ah
	;get offset from centreline
	call GetDistance
	mov bl,10
	div bl
	mov ah,0
	cmp cl,'S'
	je @f
	neg ax
@@:
	mov NavOffset,ax	       ;store it
	;find true layback
	;TrueLayback=CursorLayback*cos A + NavOffset sin A
	mov dx,CursorLayback
	movzx bx,CursorAngle
	test bl,80h		       ;is angle negative?
	je @f
	neg bl
@@:
	shl bx,1
	mov bx,CosineTable[bx]	       ;get cos value from table
	shr bx,1		       ;0-32767
	mov ax,dx
	imul bx
	shld dx,ax,1
	mov TrueLayback,dx	       ;CursorLayback* cos CursorAngle

	mov dx,NavOffset
	movzx bx,CursorAngle
	test bl,80h		       ;is angle negative?
	je @f
	neg bl
@@:
	mov al,90		       ;get sin instead of cos
	sub al,bl
	mov bl,al
	shl bx,1
	mov bx,CosineTable[bx]
	shr bx,1		       ;0-32767
	mov ax,dx
	imul bx
	shld dx,ax,1
	test CursorAngle,80h
	je @f
	neg dx
@@:
	add TrueLayback,dx

	;now adjust Offset for layback angle
	;true offset=-layback*sin A + offset cos A
	mov dx,NavOffset
	movzx bx,CursorAngle
	test bl,80h		       ;is angle negative?
	je @f
	neg bl
@@:
	shl bx,1
	mov bx,CosineTable[bx]	       ;get cos value from table
	shr bx,1		       ;0-32767
	mov ax,dx
	imul bx
	shld dx,ax,1
	mov NavOffset,dx	       ;NavOffset * cos CursorAngle

	mov dx,CursorLayback
	movzx bx,CursorAngle
	test bl,80h		       ;is angle negative?
	je @f
	neg bl
@@:
	mov al,90		       ;get sin instead of cos
	sub al,bl
	mov bl,al
	shl bx,1
	mov bx,CosineTable[bx]
	shr bx,1		       ;0-32767
	mov ax,dx
	imul bx
	shld dx,ax,1
	test CursorAngle,80h
	jne @f
	neg dx
@@:
	add NavOffset,dx

	mov ax,NavOffset
	mov TrueOffset,ax

	;now calculate postion along centre line
	mov ax,LowerLine	       ;make sure UpperLine
	mov bx,CursorLine	       ;is a higher value than
	cmp bx,ax		       ;CursorLine
	jae @f			       ;and CursorLine is higher than
	add bx,BufferSize	       ;LowerLine by adding BufferSize
	mov CursorLine,bx	       ;to compensate
@@:
	mov cx,UpperLine	       ;for buffer wraparound
	cmp cx,bx
	jae @f
	add cx,BufferSize
	mov UpperLine,cx
@@:
	mov esi,NavNorthings2
	add esi,NavNorthings1
	sar esi,1
	mov edi,NavEastings2
	add edi,NavEastings1
	sar edi,1
	;use a binary search for cursorline and map
	;the steps onto the co-ordinates
	mov bx,UpperLine
	add bx,LowerLine
	shr bx,1		       ;half way between the two
	;start off with bx as estimate
	;get initial step sizes
	;ax for line number
	;ecx for Northings
	;edx for Eastings
	mov ax,bx
	sub ax,LowerLine
	shr ax,1
	mov ecx,esi
	sub ecx,NavNorthings2
	sar ecx,1
	mov edx,edi
	sub edx,NavEastings2
	sar edx,1

NavSearch:
	cmp bx,CursorLine
	je NavLineFound
	ja @f
	add bx,ax
	add esi,ecx
	add edi,edx
	jmp NavSrch1
@@:
	sub bx,ax
	sub esi,ecx
	sub edi,edx
NavSrch1:
	sar ecx,1
	sar edx,1
	shr ax,1
	jne NavSearch
	inc ax
	jmp NavSearch

NavLineFound:
	;now calculate northing and easting ratios
	;first get distance between fixes
	mov ecx,NavNorthings1
	sub ecx,NavNorthings2
	mov NorthRatio,cx
	mov edx,NavEastings1
	sub edx,NavEastings2
	cmp FixType,2
	jae @f
	;now adjust easting for latitude
	movzx bx,NorthDegrees
	shl bx,1
	mov bx,CosineTable[bx]
	shr bx,1		       ;0-32767
	mov ax,dx
	imul bx
	shld dx,ax,1
@@:
	mov EastRatio,dx
	movsx ebx,dx
	;cx and bx hold difference in northings and eastings
	;find square root of bx^2+cx^2
	imul ebx,ebx
	imul ecx,ecx
	mov eax,ebx
	add eax,ecx
	push esi
	call SquareRoot
	pop esi
	;distance in ax
	;if there is no distance, 'No vector' error
	cmp ax,0
	jne @f
	mov si,offset ErrorMsg33
	call Rebuke
	jmp KeyDone
@@:
	mov bx,ax
	mov dx,NorthRatio
	xor ax,ax
	sar dx,1
	rcr ax,1
	sub ax,1
	sbb dx,0
	idiv bx
	mov NorthRatio,ax
	mov dx,EastRatio
	xor ax,ax
	sar dx,1
	rcr ax,1
	sub ax,1
	sbb dx,0
	idiv bx
	mov EastRatio,ax
	;EastRatio and NorthRatio are signed 16 bits values
	;now work out the effect of the layback and offset
	;NavLayback and NavOffset are in metres
	;delta northing =-(NorthRatio*Layback + EastRatio*Offset)/1.875
	mov ax,TrueLayback
	shl ax,1
	imul NorthRatio
	mov cx,dx
	mov ax,TrueOffset
	shl ax,1
	imul EastRatio
	add cx,dx
	neg cx
	;delta easting =

	mov ax,TrueOffset
	shl ax,1
	imul NorthRatio
	mov bx,dx
	mov ax,TrueLayback
	shl ax,1
	imul EastRatio
	neg dx
	add dx,bx
	;cx hold northing in metres, dx hold easting
	cmp FixType,2
	jae UTMDone
	;compensate easting for latitude by dividing by cos latitude
	xor ax,ax
	sar dx,1
	rcr ax,1
	movzx bx,NorthDegrees
	shl bx,1
	mov bx,CosineTable[bx]
	shr bx,1
	idiv bx
	;easting in ax
	;convert from metres to 1/1000s of minutes
	mov  dx,17645
	imul dx
	shld dx,ax,1
	mov bx,dx
	;easting in bx
	mov ax,cx
	mov  dx,17645
	imul dx
	shld dx,ax,1
	;northing in dx
	jmp @f
UTMDone:
	mov bx,dx
	mov dx,cx
@@:
	movsx edx,dx
	movsx ebx,bx
	add esi,edx
	add edi,ebx
WriteFixes:
	mov LongitudeFix,edi
	mov LatitudeFix,esi

	IF REPLAY
	cmp LogMode,1			;log to file?
	je LogFixes
	ENDIF
	;now write the fixes in the message and annotation boxes
	mov ebx,esi
	mov si,offset InfoMessage
	mov ch,0
	call WriteNavMinutes
	mov al,LightStatText
	mov TextColour,al
	call scrnad
	add bx,618
	mov si,offset InfoMessage
	mov ch,060h
	call ForceLength

	mov ebx,LongitudeFix
	mov si,offset InfoMessage
	mov ch,1
	call WriteNavMinutes
	call pitext
	mov AnCur,0
	jmp KeyDone


	IF REPLAY

LogFixes:
	;this writes the fix into a 82 byte string 'LogBuffer'
	mov di,offset LogBuffer
	;first fill the buffer with spaces
	mov cl,82
@@:
	mov al,' '
	mov [di],al
	inc di
	dec cl
	jnz @b
	mov di,offset LogBuffer
	mov byte ptr [di],'W'		;W=side scan sonar
	inc di
	mov si,offset AnBuff		;copy target name from anbuff
	mov cl,10
@@:
	mov al,[si]
	cmp al,0ffh
	je @f
	mov [di],al
	inc di
	inc si
	dec cl
	jnz @b
@@:
	mov AnnotationUsed,1
	mov di,(offset LogBuffer+25)	;point to latitude
	mov ebx,LatitudeFix
	mov ch,0
	call WriteDMSFix		;write to string
	mov di,(offset LogBuffer+35)	;point to longitude
	mov ebx,LongitudeFix
	mov ch,1
	call WriteDMSFix		;write to string
	;now work out day of the year
	mov si,offset DirSec
	movzx si,CURPLY
	shl si,5
	add si,(offset dirsec+13)	;point to day of month
	movzx cx,byte ptr [si]		;BCD day in cx
	cmp cl,0			;edit?
	je NullDate
	mov al,cl			;convert BCD to decimal
	and al,0f0h			;take upper digit*16
	shr al,2			;*4
	mov ah,al
	shr al,1			;*2
	add al,ah			;*6
	sub cl,al			;subtract
	movzx bx,byte ptr [si+1]	;BCD month in bx
	test bl,10h			;convert to decimal
	je @f
	sub bl,6
@@:
	dec bl				;1-12 > 0-11
	shl bx,1
	mov ax,MonthLengths[bx] 	;cummulative month length
	add cx,ax			;Julian day of year
	;now compensate for leap year
	mov al,byte ptr [si+2]		;does year/4 = int(year/4)?
	test al,10h			;its in BCD!
	je @f
	xor al,02h
@@:
	test al,03h
	jnz @f
	cmp byte ptr [si+1],2		;is month>february?
	jbe @f
	inc cx				;if so, add a day
@@:
NullDate:
	mov di,(offset LogBuffer+70)	;point to Julian day of year
	mov ax,cx			;split into digits
	mov bl,100
	div bl
	add al,'0'
	mov [di],al
	mov al,ah
	aam			       ;lower two digits
	add ax,'00'
	xchg al,ah
	mov [di+1],ax
	;now write time into string
	;get time from the cursor line
	mov ax,CursorLine
	shl ax,3
	add ax,38h
	mov gs,ax
	mov si,3c0h
	mov al,gs:[si]
	mov ah,al
	shr ah,4
	and al,0fh
	add ax,3030h
	xchg al,ah
	mov [di+3],ax			;hours
	mov al,gs:[si+1]
	mov ah,al
	shr ah,4
	and al,0fh
	add ax,3030h
	xchg al,ah
	mov [di+5],ax			;minutes
	mov al,gs:[si+2]
	mov ah,al
	shr ah,4
	and al,0fh
	add ax,3030h
	xchg al,ah
	mov [di+7],ax			;seconds
	mov word ptr [di+10],0a0dh	;CR/LF
	;LogBuffer is now filled in
	;now write it to the DOS file LogFileName
	call SwitchToRealMode
	;first try to open the file
	mov ah,3dh			;open file
	mov al,1			;write access
	mov dx,offset LogFileName
	int 21h
	jc CreateNew
	;now move file pointer to the end of the file
	mov LogFileHandle,ax
	mov bx,ax			;handle
	mov ax,4202h
	mov cx,0
	mov dx,0
	int 21h
	mov ax,LogFileHandle
	jmp @f


CreateNew:
	;create a new file
	mov ah,3ch			;create file
	mov cx,0
	mov dx,offset LogFileName
	int 21h
	mov LogFileHandle,ax
@@:
	mov bx,ax			;write LogBuffer
	mov ah,40h
	mov cx,82
	mov dx,offset LogBuffer
	int 21h

	mov bx,LogFileHandle
	mov ah,3eh
	int 21h

	call SwitchToProtMode
	jmp KeyDone


WriteDMSFix:
	;this converts a value in ebx of 1/1000s of minutes
	;to a string 'ddmmss.ss' (northings) or 'dddmmss.ss' (eastings)
	;the string is written to [di]
	;ch=0 for northings, 1 for eastings
	cmp ebx,0
	jge @f
	neg ebx 		       ;get abs value
	or ch,2 		       ;bit 1 of ch=negative value
@@:
	mov ax,bx
	shr ebx,16		       ;conv ebx to dx:ax for division
	mov dx,bx		       ;by 60000 to give degrees and
	mov bx,60000		       ;1/1000s of minutes
	div bx			       ;degrees in ax, 1/1000 minutes in dx
	test ch,1
	je WriteDMS1
	mov ah,'0'		       ;sort out 100s of degrees if
	cmp al,100		       ;value is easting
	jb @f
	sub al,100
	inc ah
@@:
	mov [di],ah
	inc di
WriteDMS1:
	aam			       ;lower two degrees digits
	add ax,'00'
	xchg al,ah
	mov [di],ax
	;now divide by 1000 to get minutes
	mov ax,dx			;1/1000ths of minutes in ax
	xor dx,dx
	mov bx,1000
	div bx
	;minutes in ax, minutes*1000 in dx
	aam			       ;two minutes digits
	add ax,'00'
	xchg al,ah
	mov [di+2],ax
	;now get seconds
	mov ax,60
	mul dx
	mov bx,1000
	div bx
	;seconds in ax, thousandths in dx
	aam			       ;two seconds digits
	add ax,'00'
	xchg al,ah
	mov [di+4],ax
	mov ax,dx
	mov bl,10
	div bl
	aam			       ;two decimal seconds digits
	add ax,'00'
	xchg al,ah
	mov byte ptr [di+6],'.'
	mov [di+7],ax
	mov ax,'EW'
	test ch,1
	jne @f
	mov ax,'NS'
@@:
	test ch,2
	jne @f
	xchg al,ah
@@:
	mov [di+9],al
	ret

	ENDIF

InvNavMsg:
	mov si,offset ErrorMsg28
	jmp @f
TopOfScreen:
	mov si,offset ErrorMsg26
@@:
	call Rebuke
	jmp KeyDone

WriteNavMinutes:
	cmp FixType,2
	jae WriteUTMMetres
	;this converts a value in ebx of 1/1000s of minutes
	;to a string 'ddmm.mmm' (northings) or 'dddmm.mmm' (eastings)
	;the string is written to [si]
	;ch=0 for northings, 1 for eastings
	cmp ebx,0
	jge @f
	neg ebx 		       ;get abs value
	or ch,2 		       ;bit 1 of ch=negative value
@@:
	mov ax,bx
	shr ebx,16		       ;conv ebx to dx:ax for division
	mov dx,bx		       ;by 60000 to give degrees and
	mov bx,60000		       ;1/1000s of minutes
	div bx			       ;degrees in ax, minutes in dx
	test ch,1
	je WriteNav1
	mov ah,'0'		       ;sort out 100s of degrees if
	cmp al,100		       ;value is easting
	jb @f
	sub al,100
	inc ah
@@:
	mov [si],ah
	inc si
WriteNav1:
	aam			       ;lower two digits
	add ax,'00'
	xchg al,ah
	mov [si],ax
	add si,2
	mov byte ptr [si],'*'
	inc si
	;now get minutes
	xor ax,ax
	xchg ax,dx
	mov bx,10000
	div bx
	add al,'0'
	mov [si],al
	inc si
	xor ax,ax
	xchg ax,dx
	mov bx,1000
	div bx
	add al,'0'
	mov [si],al
	inc si
	mov byte ptr [si],'.'
	inc si
	xor ax,ax
	xchg ax,dx
	mov bx,100
	div bx
	add al,'0'
	mov [si],al
	inc si
	mov al,dl
	aam
	add ax,'00'
	xchg al,ah
	mov [si],ax
	;now work out compass letter

	mov ax,'EW'
	test ch,1
	jne @f
	mov ax,'NS'
@@:
	test ch,2
	jne @f
	xchg al,ah
@@:
	mov [si+2],al
	mov byte ptr [si+3],0ffh
	ret

WriteUTMMetres:
	;this converts a value in ebx metres
	;the string is written to [si]
	;ch=0 for northings, 1 for eastings
	cmp EastNorth,1
	je @f
	mov ax,' Y'
	sub al,ch
	jmp WriteNE
@@:
	mov ax,' E'
	cmp ch,1
	je WriteNE
	mov ax,' N'
WriteNE:
	mov [si],ax		       ;X or Y
	add si,2
	mov al,'+'
	cmp ebx,0
	jge @f
	neg ebx 		       ;get abs value
	mov al,'-'
@@:
	mov [si],al
	inc si
	mov eax,'0000'
	mov [si],eax
	mov [si+4],eax
	mov byte ptr [si+8],0ffh
	add si,7
	mov eax,ebx
	mov ebx,10
@@:
	xor edx,edx
	div ebx
	add dl,'0'
	mov [si],dl
	dec si
	cmp eax,0
	jne @b
	ret


GetNavMinutes:
	;this extracts a value, in 1/1000s of a minute
	;from a string with the format ddmm.mmm,X (northings X='N' or 'S')
	;or dddmm.mmm,X (eastings X='E' or 'W')
	;this string is at [si]
	;first get degrees (180 max)
	mov ch,0
	mov al,0
	cmp byte ptr [si+4],'.'     ;northings have 2 degree digits
	je @f			       ;eastings have 3
	inc ch			       ;ch=0 for northings, 1 for eastings
	inc si
	cmp byte ptr [si-1],'1'     ;first digit of eastings is 0 or 1
	jne @f
	mov al,100
@@:
	mov ah,[si]		    ;get 10s of degrees
	sub ah,'0'		       ;multiply by 10
	shl ah,1
	add al,ah
	shl ah,2
	add al,ah
	inc si
	mov ah,[si]
	sub ah,'0'		       ;add in units
	add al,ah
	test ch,1
	jne @f
	mov NorthDegrees,al
@@:
	movzx bx,al
	inc si
	;now multiply degrees by 60000 to get 1/1000s of minutes
	mov ax,60000
	mul bx
	mov bx,dx
	shl ebx,16
	mov bx,ax
	;result in ebx

	;si points to minutes

	mov cl,5		       ;5 digits
	xor dx,dx		       ;total 1/1000s of minutes
	mov ax,dx
GetNavM1:
	shl dx,1
	mov ax,dx
	shl dx,2
	add dx,ax		       ;multiply dx by 10
	movzx ax,byte ptr [si]	    ;get digit
	cmp al,','		       ;if the last digit is a comma
	jne @f			       ;it is a NMEA0183B message with
	mov al,'0'		       ;hundredths, not thousandths of
	mov cl,1		       ;must be the last digit
	dec si
@@:				       ;minutes
	sub al,'0'
	add dx,ax		       ;add into total
	inc si
	cmp byte ptr [si],'.'	    ;skip decimal point
	jne @f
	inc si
@@:
	dec cl
	jnz GetNavM1
	dec si
	movzx edx,dx
	add ebx,edx		       ;add into grand total
	mov cl,1		      ;now get sign
	call FindParameter
	cmp byte ptr [si],'N'
	je @f
	cmp byte ptr [si],'E'
	je @f
	neg ebx
@@:
	ret			       ;value in ebx


PLINE:	;THIS PRINTS THE LINES FORM THE BUFFER line ax TO
	;THE SCREEN, SCALING BOTH X and Y
	shl AX,03H		       ;CALCULATE SOURCE SELECTOR
	add AX,038H		       ;and PUT IT IN GS
	mov GS,AX
	;get some values from the scan line
	mov ax,gs:[0f80h]		;time (hours & minutes)
	mov LTime,ax
	mov ax,gs:[0f83h]		;range
	mov LRange,al
	mov ax,gs:[0f84h]
	mov LAltitude,al		;altitude
	mov ax,gs:[0f8eh]
	mov LVNumber,ax 		;event mark number
	mov al,gs:[0f8ch]
	mov LSpeed,al			;speed
	mov eax,gs:[0f90h]
	mov si,offset LAnnotation	;annotation text and position
	mov eax,gs:[0f90h]
	mov [si],eax
	mov eax,gs:[0f94h]
	mov [si+4],eax
	mov eax,gs:[0f98h]
	mov [si+8],eax
	mov al,gs:[0f8dh]
	mov LFeatures,al
	mov ax,gs:[0ffeh]
	mov LSounding,ax

	;mov work out ScrollDrop

	;at 100m range each pixel=200/640m=0.3125m
	;also ping rate at 100m=0.2s
	;at 0.1m/s 1 pixel down=0.02m
	;therefore compression is 0.02/0.3125
	;=0.064
	;4194/65536

	;if not in map mode mode, display each scan line
	mov ax,word ptr ScreenZoom     ;set writezoom/pan to either
	shl ah,2		       ;screenzoom/pan or redrawzoom/pan
	test RedrawLine,1
	je @f
	mov ax,word ptr RedrawZoom
@@:
	mov word ptr WriteZoom,ax

	movzx bx,LSpeed		       ;get speed in bx
	mov dl,1
	test WriteZoom,1	       ;any zoom
	je @f
	mov dl,2
	shl bx,1		       ;x2
	test WriteZoom,4
	je @f
	mov dl,4
	shl bx,1		       ;x4
@@:
	test ScreenGeometry,2
	je LinePerPing		       ;jump if not in map mode
	mov ax,4194		       ;factor (see above)
	mul bx
	test RedrawLine,1
	je @f
	add ax,RedrawRemain
	mov RedrawRemain,ax
	jmp yscale
@@:
	add ax,NewlineRemain
	mov NewlineRemain,ax
yscale:
	jnc @f
	inc dl
@@:
LinePerPing:
	mov ScrollDrop,dl
	cmp dl,0		       ;if there are no lines to be printed
	jne @f			       ;finish now
	ret
@@:
	cmp LookBackScrl,2	       ;look back up?
	je TigTog1
	test RedrawLine,1	       ;is it a redraw line?
	jne WriteToScreen	       ;if so, jump
	test HideMouse,1
	jne @f
	call RemoveArrow	       ;erase arrow
@@:
	call ScrollDown 	       ;scroll screen before printing
	test HideMouse,1
	jne @f
	call PrintArrow		       ;draw arrow
@@:
	jmp WriteToScreen
TigTog1:
	mov ah,80		       ;adjust RedrawAddress
	mov al,dl		       ;80 bytes per line
	mul ah
	sub RedrawAddress,ax
WriteToScreen:
	;THIS WRITES THE BUFFER LINE LNSEG
	;TO THE SCREEN LINE 4160 or RedrawAddress
	;THE LINES ARE X SCALED ACCORDING TO THE ZOOM FACTOR
	;THE DATA IS SCALED INTO A 640 byte BUFFER BEFORE
	;BEING WRITTEN TO THE SCREEN
	;THIS AVOIDS MULTIPLE SEGMENT REGISTER RELOADING


	test ScreenGeometry,3		       ;IS SO or TA MODE ON?
	je Disp1		       ;jump if not

	;slant range correct the line into 'SRCBuffer'
	call ScaleAltitude	       ;scale the Altitude
	add ax,20		       ;skip over 'ring'
	movzx esi,AX		       ;SI=SOURCE POINTER
	mov eax,SquaresTable[esi*4]
	mov AltitudeSquared,EAX	       ;AltitudeSquared=(SCALED Altitude)^2
	mov DX,0		       ;DESTINATION COUNT
	mov CH,0		       ;INITIALIZE REPEAT LIMIT COUNTER
DISP6:

	mov al,gs:[si+1920]		;transfer port byte
	mov di,(offset SRCBuffer+1920)
	add di,dx
	mov [di],al

	mov bx,1920
	sub bx,si
	mov al,gs:[bx]			;transfer starboard byte
	mov di,(offset SRCBuffer+1919)
	sub di,dx
	mov [di],al
	inc ch			       ;INCREASE REPEAT COUNTER
	cmp ch,4		       ;CHECK REPEAT LIMIT
	jz @f			       ;IF EXCEEDED, INCREASE SOURCE

	movzx ebx,dx
	mov EAX,SquaresTable[EBX*4]	;EAX=DESTINATION SQUARED
	add EAX,AltitudeSquared

	movzx ebx,si
	cmp eax,SquaresTable[ebx*4]
	jb DISP4
@@:
	mov CH,0		       ;RESET REPEAT LIMIT COUNTER
	inc SI			       ;INCREASE SOURCE POINTER
DISP4:
	inc DX
	cmp si,1919		       ;FINISH WHEN SOURCE=1919
	jb DISP6
	mov di,(offset SRCBuffer+1920)	;NOW FILL IN THE REMAINING
	mov si,(offset SRCBuffer+1919)	;DESTINATION BUFFER WITH BLANKS
	add di,dx		       ;DI=RIGHT
	sub si,dx		       ;SI=LEFT
	mov AL,00H		       ;AL=COLOUR
@@:
	mov [DI],AL		       ;WRITE THE COLOUR
	mov [SI],AL
	inc DI			       ;MOVE THE POINTERS
	dec SI
	inc DX			       ;INCREASE THE COUNT
	cmp DX,1920
	jne @b

	movzx si,WritePan
	shl si,2
	mov bx,si		       ;bx=4*pan
	shl si,4
	sub si,bx		       ;SI=60*PAN
	add si,offset SRCBuffer
	mov di,offset TmpBuf	       ;START OF TEMPORARY BUFFER

	mov al,WriteZoom	       ;THE SCAN LINE IS FIRST SCALED INTO
	test al,1		       ;THE TEMPORARY BUFFER
	jne SRCorrect1

	;compress 6>1 for 1x zoom
	mov si,offset SRCBuffer	       ;PAN MUST BE 0
	mov cx,640		       ;ZOOM AT X1 SO X SCALE 6>1
@@:
	mov ax,[si]			;[DI]=([si]+[si+1]+[si+3]+[si+4])/4
	add al,[si+3]
	rcr al,1
	add ah,[si+4]
	rcr ah,1
	add al,ah
	rcr al,1
	mov [di],al
	add si,6
	inc di
	loop @b
	JMP XFIN		       ;DONE

SRCorrect1:
	test AL,04H
	jne SRCorrect2

	;compress 3>1 for zoom x2
	mov cx,640		       ;
@@:
	mov ax,[si]			;[DI]=([si]+[si+1])/2
	add al,ah
	rcr al,1
	mov [di],al
	add si,3
	inc di
	loop @b
	JMP XFIN		       ;DONE

SRCorrect2: ;compress 3>2 for zoom x4
	mov cx,320
@@:
	mov ax,[si]			;
	mov [di],ax
	add si,3
	add di,2
	loop @b
	jmp XFin

DISP1:	;normal geometry comes here
	movzx si,WritePan
	shl si,2
	mov bx,si		       ;bx=4*pan
	shl si,4
	sub si,bx		       ;SI=60*PAN
	mov di,offset TmpBuf	       ;START OF TEMPORARY BUFFER

	mov al,WriteZoom	       ;THE SCAN LINE IS FIRST SCALED INTO
	test al,1		       ;THE TEMPORARY BUFFER
	jne BUFFZO

	;compress 6>1 for 1x zoom
	mov si,0		       ;PAN MUST BE 0
	mov cx,640		       ;ZOOM AT X1 SO X SCALE 6>1
@@:
	mov ax,gs:[si]			;[DI]=([si]+[si+1]+[si+3]+[si+4])/4
	add al,gs:[si+3]
	rcr al,1
	add ah,gs:[si+4]
	rcr ah,1
	add al,ah
	rcr al,1
	mov [di],al
	add si,6
	inc di
	loop @b
	;add altitude track
	test DisplayFlags,02H	       ;Altitude marks/trace on?
	je XFin
	test HideShowFlag,1
	jne XFin
	inc TraceColour
	test TraceColour,4
	je XFin
	call ScaleAltitude
	mov bl,6
	div bl
	movzx bx,al
	mov di,(offset TmpBuf+320)
	mov byte ptr [di+bx],0
	sub di,bx
	dec di
	mov byte ptr [di],0
	JMP XFIN		       ;DONE

BUFFZO:
	test AL,04H
	jne BUFFZT

	;compress 3>1 for zoom x2
	mov cx,640		       ;
@@:
	mov ax,gs:[si]			;[DI]=([si]+[si+1])/2
	add al,ah
	rcr al,1
	mov [di],al
	add si,3
	inc di
	loop @b
	;add altitude track
	test DisplayFlags,02H	       ;Altitude marks/trace on?
	je XFin
	test HideShowFlag,1
	jne XFin
	inc TraceColour
	test TraceColour,4
	je XFin
	call ScaleAltitude
	mov bx,3
	xor dx,dx
	div bx
	mov bx,ax
	movzx si,WritePan
	mov di,(offset TmpBuf+640)
	shl si,2
	sub di,si
	shl si,2
	sub di,si
	lea si,[di+bx]
	cmp si,(offset TmpBuf+638)
	ja @f
	mov word ptr [si],0
@@:
	neg bx
	sub di,2
	lea si,[di+bx]
	cmp si,(offset TmpBuf+638)
	ja @f
	mov word ptr [si],0
@@:
	JMP XFIN		       ;DONE

BUFFZT: ;compress 3>2 for zoom x4
	mov cx,320
@@:
	mov ax,gs:[si]			;
	mov [di],ax
	add si,3
	add di,2
	loop @b
	;add altitude track
	test DisplayFlags,02H	       ;Altitude marks/trace on?
	je XFin
	test HideShowFlag,1
	jne XFin
	inc TraceColour
	test TraceColour,4
	je XFin
	call ScaleAltitude
	shl ax,1
	mov bx,3
	xor dx,dx
	div bx
	mov bx,ax
	movzx si,WritePan
	mov di,(offset TmpBuf+1280)
	shl si,3
	sub di,si
	shl si,2
	sub di,si
	lea si,[di+bx]
	cmp si,(offset TmpBuf+636)
	ja @f
	mov dword ptr [si],0
@@:
	neg bx
	sub di,2
	lea si,[di+bx]
	cmp si,(offset TmpBuf+636)
	ja @f
	mov dword ptr [si],0
@@:

XFIN:	;BUFFER IS NOW EXPANDED
	;THE LINE IS NOW WRITTEN FROM TMPBUF TO THE SCREEN
	mov DI,RedrawAddress	       ;SET DI AT REDRAW SCREEN addRESS
	test RedrawLine,1	       ;IF PLINE IS For REDRAW
	jnz @f			       ;LEAVE DI
	call SCRNAD		       ;OTHERWISE SET DI TO THE TOP
	lea DI,[BX+4160]	       ;OF THE ACTIVE WINDOW
@@:
	test DisplayFlags,40H	       ;ARE RANGE LINES NEEDED
	je NOSLIN		       ;if not, jump
	test HideShowFlag,1
	jne NoSlin
	test WriteZoom,01H	       ;is zoom on?
	jne SLIN24		       ;if so, jump
	;do range lines for X1 zoom
	mov AL,9
	mov SI,offset TMPBUF+040H
SLINL1:
	mov byte PTR [SI],0H
	add SI,040H
	dec AL
	jnz SLINL1
	JMP NOSLIN		       ;done

SLIN24:
	movzx ax,WritePan
	test WriteZoom,04H	       ;is zoom X2 or X4?
	jne SLIN4		       ;if X4, jump
	;do range lines for X2
	xor si,si
	sub si,ax
	shl si,2
	sub si,ax
	shl si,2
	;si= -20*WritePan
SLINL2:
	cmp SI,639		       ;if si
	JG NOSLIN
	cmp SI,0
	JL @f
	mov byte PTR [SI+TMPBUF],0H
@@:
	add SI,080H
	JMP SLINL2

SLIN4:				       ;RANGE LINES For X4
	xor si,si
	sub si,ax
	shl si,2
	sub si,ax
	shl si,3		       ;si=-40*WritePan
SLINL5:
	cmp SI,639
	JG NOSLIN
	cmp SI,0
	JL @f
	mov byte PTR [SI+TMPBUF],0H
@@:
	add SI,0100H
	JMP SLINL5

NOSLIN:

	mov SI,offset TMPBUF	       ;SI=TEMPORARY BUFFER
	mov ch,080H		       ;PRINT A 640 PIXEL LINE
	mov DX,03CEH		       ;FROM DATA AT TMPBUF
	mov AL,08H		       ;point vga index to bit mask
	out DX,AL
	inc DX
	mov cl,80
pln1:
	mov AH,ScrollDrop	       ;AH IS number of lines down
	mov AL,ch
	out DX,AL		       ;SET THE BIT MASK
	mov al,es:[di]		       ;dummy read
	mov AL,[SI]		       ;get pixel
	test RedrawLine,1
	je ContrastDone
	cmp ContrastMul,0
	je ContrastDone
	cmp ContrastMul,2		;x4?
	je ContrastX4
	;x2 contrast
	sub al,ContrastOff
	jnc @f
	mov al,0
@@:
	cmp al,127
	jbe @f
	mov al,127
@@:
	shl al,1
	jmp ContrastDone

ContrastX4:
	sub al,ContrastOff
	jnc @f
	mov al,0
@@:
	cmp al,63
	jbe @f
	mov al,63
@@:
	shl al,2
	jmp ContrastDone

ContrastDone:
	mov bx,offset LogsTable
	xlatb LogsTable
	xor AL,invpal
	shr al,4
	mov bx,offset ScreenGamma
	test DisplayFlags,80h	       ;false colour?
	je @f
	add bx,16
@@:
	xlatb fs:ScreenGamma
	mov ES:[DI],AL		       ;WRITE THE PIXEL
	dec ah
	je @f
	mov ES:[DI+80],AL	       ;2nd line
	dec ah
	je @f
	mov ES:[DI+160],AL	       ;3rd line
	dec ah
	je @f
	mov ES:[DI+240],AL	       ;4th line
	dec ah
	je @f
	mov ES:[DI+320],AL	       ;5th line
	dec ah
	je @f
	mov ES:[DI+400],AL	       ;6th line
	dec ah
	je @f
	mov ES:[DI+480],AL	       ;7th line
	dec ah
	je @f
	mov ES:[DI+560],AL	       ;8th line
@@:
	inc SI			       ;INCREASE THE SOURCE POINTER
	Ror ch,1		       ;increase the video address if
	JNC pln1		       ;the bit mask rolls round
	inc DI
	dec cl
	jnz PLN1		       ;print 640 pixels
	RET			       ;END OF WRTLN

SETGCR: mov DX,03CEH		       ;AL=INDEX  AH=VALUE
	out DX,AL		       ;THIS SETS THE VGA GRAPHICS
	inc DX			       ;CONTROLLER REGISTER AL
	mov AL,AH		       ;WITH THE VALUE AH
	out DX,AL
	RET

SCRNAD: mov DX,03D4H		       ;RETURNS addR OF TOP OF SCREEN IN BX
	mov AL,0DH		       ;USES AX,BX and DX
	out DX,AL
	inc DX
	IN AL,DX
	mov BL,AL
	dec DX
	mov AL,0CH
	out DX,AL
	inc DX
	IN AL,DX
	mov BH,AL
	RET


Scrolldown:
	;this scrolls the screen by 'ScrollDrop' lines (1-8)

	mov dx,03dah		       ;vga input status register 1
@@:
	in al,dx		       ;wait for retrace to stop jitter
	test al,8
	jnz @b			       ;low
@@:
	in al,dx
	test al,8		       ;high
	jz @b
	mov dx,3000		       ;delay
@@:
	dec dx
	jnz @b
	;first ScrollDepth (ScrollDrop*80)bytes is calculated
	mov ah,80
	mov al,ScrollDrop
	mul ah
	mov ScrollDepth,ax

	test FreezeMode,1	       ;IF FREEZE MODE IS ON, SCROLL
	jne FreezeScroll	       ;TOP 84 LINES DOWN
	SUB ARROW,ax		       ;adjust arrow position
	sub CursorAddress,ax
	;HARDWARE SCROLL DOWN
	;THIS WORKS BY READING THE
	;addRESS OF THE TOP OF THE
	;SCREEN, SUBTRACTING 'ScrollDepth'
	;and WRITING THIS TO
	;THE ORIGIN CONTROL REGISTER
	mov DX,03D4H		       ;point index to origin high byte
	mov AL,0cH
	out DX,AL
	inc DX
	IN AL,DX		       ;read it
	mov ah,al
	dec DX
	mov AL,0dH		       ;point index to low byte
	out DX,AL
	inc DX
	IN AL,DX		       ;origin in ax
	sub ax,ScrollDepth
	out dx,al		       ;write low byte
	dec dx
	mov AL,0cH		       ;point index to high byte
	out DX,AL
	inc DX
	mov al,ah
	out dx,al		       ;write high byte

	call SCRNAD
	mov di,bx
	mov si,bx
	mov CX,4160
	add si,ScrollDepth
	mov AL,05H		       ;SET WRITE MODE 1
	mov AH,01H		       ;READ MODE 0
	call SETGCR
	rep movsb es:[di],es:[si]
	mov AL,05H		       ;SET WRITE MODE 2
	mov AH,02H		       ;READ MODE 0
	call SETGCR
	;now soft scroll the screenmap 'ScrollDrop' lines down
	mov cx,428		       ;count
	mov di,854
	movzx si,ScrollDrop
	shl si,1
	add si,di
@@:
	mov ax,ScreenLineMap[di]
	mov ScreenLineMap[si],ax
	sub si,2
	sub di,2
	loop @b
	RET

Freezescroll:			       ;THIS SOFT SCROLLS THE UPPER
	mov SI,9039		       ;WINDOW IN FREEZE MODE
	mov CX,4880
	mov bx,ScrollDepth
	sub cx,bx
	cmp FreezeMode,3
	je @f
	cmp RedrawMapLine,64	       ;dont change address if in lower window
	jae @f
	add RedrawAddress,bx
@@:
	mov DI,si
	sub si,bx
	call SCRNAD
	add SI,BX
	add DI,BX
	mov ax,0105H		       ;set write mode 1
	call SETGCR
	std
	rep movsb es:[di],es:[si]
	cld
	mov ax,0205H		       ;SET WRITE MODE 2
	call SETGCR
	;now scroll the screenmap down
	mov cx,59
	mov di,118		       ;count and index
	movzx si,ScrollDrop
	shl si,1
	add si,di
@@:
	mov ax,ScreenLineMap[di]
	mov ScreenLineMap[si],ax
	sub si,2
	sub di,2
	loop @b
	RET


ResetUart:		       ;RESET 6402
	mov DX,0211H
	mov AL,03H
	or al,CoaxPower
	out DX,AL
	mov CX,0100H
@@:
	LOOP @b
	dec al
	out DX,AL
	ret

	;range	scan bytes
	;50	1280
	;100	2560
	;125	3200
	;150	3840
	;200	5120
	;250	6400
	;300	7680

	;HF monitor and ping=20
	;LF monitor and ping=



CalcNewRange:
	;find the new range from the line lentgh in ax
	mov bx,ax
	mov al,0			;50HF
	cmp bx,514h
	je @f

	mov al,1			;100HF
	cmp bx,0a14h
	je @f

	mov al,2			;125HF
	cmp bx,0c94h
	je @f

	mov al,3			;150HF
	cmp bx,0f14h
	je @f

	;now look for LF ranges
	mov al,88h			;100LF
	cmp bx,0a18h
	je @f

	mov al,84h			;200LF
	cmp bx,01418h
	je @f

	mov al,85h			;300LF
	cmp bx,01e18h
	je @f

	mov al,86h			;400LF
	cmp bx,02818h
	je @f

	mov al,07h			;75HF
	cmp bx,0794h
	je @f

	mov bx,100		       ;if the new range is invalid
	mov al,5		       ;come here
	mov LinkError,1		       ;bad link
	;jmp TempBreak
	ret

@@:
	cmp al,RangeNumber	       ;is the range different?
	je TempBreak
	mov NewRangeFlag,01H	       ;signal new range
	mov RangeNumber,AL	       ;store new range number
TempBreak:
	mov LineLength,BX	       ;store new line length
	RET			       ;finished


PMARK:	;THIS PRINTS A black LINE AT BX

	mov AL,08H
	mov AH,0FFH
	call SETGCR		       ;SET BIT MASK TO ALL BITS ON
	mov CL,050H		       ;EIGHTY BYTES
	mov AL,0FH
PMRK1:
	mov ES:[BX],AL		       ;WRITE EIGHT PIXELS
	inc BX			       ;INCREASE POINTER
	dec CL
	jnz PMRK1
	RET

PrintDelineation:
	;this prints a white line across the top of the screen
	mov AL,08H
	mov AH,0FFH
	call SETGCR		       ;SET BIT MASK TO ALL BITS ON
	mov CL,050H		       ;EIGHTY BYTES
	mov AL,0
@@:
	mov ES:[BX],AL		       ;WRITE EIGHT PIXELS
	mov es:[bx+80],al
	inc BX			       ;INCREASE POINTER
	dec CL
	jnz @b
	RET

PANNO:	;THIS PRINTS THE ANNOTATION TEXT FROM BUFFER LINE
	;first the pan position for the annotation is found
	;the annotation may not be visible if zoom is on
	;LAnPosition is the position across the screen 0-159
	mov AL,WriteZoom	       ;FIRST SEE IF ANNOTATION IS VISIBLE
	test AL,01H		       ;if zoom is x2 or x4, jump
	jne PRANN1
	;no zoom, annotation must be visible
	movzx ax,LAnPosition
	shr ax,1
	add BX,AX
	JMP PRANN2

PRANN1: ;if zoom is x2 or x4
	;check if text is off to the left of the picture
	mov AH,WritePan		       ;find WritePan*2.5
	mov al,ah
	shl AH,1
	shr al,1
	add AH,al
	mov AL,LAnPosition
	cmp AL,AH		       ;IF LAnPosition<2.5*WritePan, the text
	jae PRANN4		       ;is to the left of the picture
	RET			       ;so finish
PRANN4:
	test WriteZoom,04H
	jne PRANN3		       ;IF X4 JUMP
	;if zoom is x2, check if text is off to the right of the picture
	add AH,80		       ;IF LAnPosition>=(2.5*WritePan+80),
	cmp AL,AH		       ;finish
	jb @f
	RET
@@:
	sub ah,80		       ;ah=2.5*WritePan
	SUB AL,AH		       ;FIND PHYSICAL PAN
	mov AH,0
	add BX,AX
	JMP PRANN2

PRANN3: ;COME HERE For ZOOM FACTor 4
	;if zoom is x4, check if text is off to the right of the picture
	add AH,40		       ;IF LAnPosition>=(2.5*WritePan+40),
	cmp AL,AH		       ;finish
	jb @f
	RET
@@:
	sub ah,40
	SUB AL,AH
	mov AH,0
	shl AX,1
	add BX,AX
PRANN2: ;PRINT THE ACTUAL TEXT AT BX
	mov SI,offset LAnnotation
	;this prints small text from [si] to screen at bx
	;string must end in 0FFh
FIXAN:	;ENTRY POINT FROM FIX ANNOTATION
	mov al,AnnotationBack
	shl al,4
	or al,AnnotationFore
	mov TextColour,al	       ;set colour to black on white
smtext: ;entry point for status line text
	push SI
	cmp byte PTR [SI],0FFH	       ;IF THE FIRST byte OF ANNOTATION
	jne PRNB9		       ;IS 0FFH, EXIT
	pop SI
	RET
PRNB9:
	;First the length of the string in pixels is found in cx
	;so that a background may be blanked out
	mov cx,1		       ;Initailize total with 1
PRANB1:
	mov AL,[SI]		       ;get character from string
	cmp AL,0FFH		       ;end of string?
	je PRANB2		       ;if so, end calculation
	sub al,20h		       ;ascii adjust
	cmp al,5fh
	jbe @f
	mov al,0
@@:
	mov AH,0		       ;get char*8 in AX
	shl AX,3		       ;start of font in DI
	mov di,ax		       ;find offset of character in DI
	mov AL,FS:FontA[DI+7]	       ;get x size (0-7) from bits 0-2
	and AL,07H		       ;from last byte of character font
	inc al			       ;inter-character space
	mov ah,0
	add cx,ax		       ;add this to total
	inc SI			       ;increase character pointer
	JMP PRANB1		       ;loop round
PRANB2:
	;adjust screen address if the text would wrap round
	push bx 		       ;save screen address
	mov di,bx
	call ScrnAd		       ;get origin in bx
	sub di,bx
	mov ax,di		       ;difference in ax
	mov di,80
	xor dx,dx
	div di			       ;divide by 80, remainder in dl (0-79)
	mov ax,cx		       ;length of string in pixels
	shr ax,3		       ;length in characters
	add al,dl
	sub al,79
	pop bx
	js @f
	mov ah,0
	sub bx,ax
@@:
	;now print int(cx/8) 8x10 pixel blocks
	push BX 		       ;save screen address
	mov DX,03CEH
	mov AL,8		       ;POINT VGA INDEX TO BIT MASK
	out DX,AL
	inc DX			       ;point to vga data register
	mov AL,0FFH		       ;bit mask is 11111111b
	out DX,AL		       ;set it
	test cx,0fff8H		       ;if length<8 pixels, jump out
	jz PRNB8
PRANB3:
	mov AH,0AH		       ;background is 10 lines down
PRANB4:
	mov AL,ES:[BX]		       ;dummy read
	mov al,TextColour	       ;get colour
	shr al,4		       ;background colour
	mov ES:[BX],al		       ;write white line
	add BX,050H		       ;next screen line down
	dec AH			       ;line counter
	jnz PRANB4		       ;loop 10 times
	SUB BX,799		       ;restore screen address and advance it
	SUB cx,08H		       ;decrease length by 8
	test cx,0fff8H		       ;is length still>7?
	jnz PRANB3		       ;if so, loop back
PRNB8:
	;now print the remaining 0-7 pixels
	;remaining length in CL
	Xor CL,07H		       ;invert it
	inc CL			       ;plus one
	mov AL,0FFH		       ;bit mask in al
	shl AL,CL		       ;shift left by CL
	out DX,AL		       ;set bit mask
	mov AH,0AH		       ;10 lines down
PRANB5:
	mov AL,ES:[BX]		       ;dummy read
	mov al,TextColour		       ;get colour
	shr al,4		       ;background colour
	mov ES:[BX],al		       ;write white row
	add BX,050H		       ;next screen line down
	dec AH			       ;count
	jnz PRANB5		       ;loop 10 times
	pop BX			       ;restore screen address
	pop SI			       ;restore string pointer
	mov CL,1		       ;shift offset in CL
	out DX,AL
	add BX,050H		       ;add one row to screen address

PRANT1:
	;now the text is printed within the block
	mov DX,03CFH
	mov AL,[SI]		       ;get character from string
	cmp AL,0FFH		       ;if it is 0FFh,
	je PRANTF		       ;jump to finish
	sub al,20h		       ;ascii adjust
	cmp al,5fh
	jbe @f
	mov al,0
@@:
	mov AH,0		       ;get character*8 in AX
	shl AX,3
	mov DI,offset FontA	       ;DI=start of small font
	add DI,AX		       ;DI=offset of character in font
	mov CH,8		       ;characters are 8 rows down
	push BX 		       ;save screen address
PRANT2:
	mov AH,FS:[DI]		       ;get line from font
	and AH,0F8H		       ;mask out size if 8'th byte
	mov AL,00		       ;form shift register from AX
	shr AX,CL		       ;shift right by x offset
	XCHG AL,AH		       ;swop bytes
	out DX,AL		       ;output high byte as bit mask
	mov DL,ES:[BX]		       ;dummy read to DL
	mov dl,TextColour		       ;get colour
	and dl,0fh		       ;foreground colour
	mov ES:[BX],dl		       ;write black pixels
	mov DL,0CFH		       ;restore vga address in DX
	mov AL,AH		       ;get second byte in AL
	out DX,AL		       ;write bit mask
	mov DL,ES:[BX+1]	       ;dummy read to DL
	mov dl,TextColour		       ;get colour
	and dl,0fh		       ;foreground colour
	mov ES:[BX+1],dl	       ;write black pixels
	mov DL,0CFH		       ;restore DL
	inc DI			       ;increase font pointer
	add BX,050H			 ;screen address down one r

	dec CH			       ;row count

	jnz PRANT2		       ;loop back 8 tim

	pop BX			       ;restore screen addre

	mov al,FS:[DI-1]	       ;get character width from last font
	and AL,07H		       ;byte, bits 0-2 in AL
	inc al
	add CL,AL		       ;add this to shift offset
	test CL,0F8H		       ;if this>8, mask it with 07h
	jz PRANT3
	and CL,07H		       ;and increment the screen address
	inc BX
PRANT3:
	inc SI			       ;increment string pointer
	JMP PRANT1		       ;loop back

PRANTF: RET			       ;finished here


PrintArrow:
	;this prints the annotation arrow at 'arrow'
	;it is shifted right by 'MouseXCoord' & 07h pixels
	;test InitRedraw,02H	       ;IS A REDRAW IN PROGRESS?
	;jne PARRF		       ;IS SO, DO NOTHING
	mov si,ARROW		       ;get address in si
	cmp MouseXCoord,FlipOver
	jl @f
	SUB si,2
@@:
	mov bx,si		       ;copy it into si
	mov RemoveAddress,bx
	;first a 3x10x4 plane background is stored in arrbuf (120 bytes)
	mov DI,offset ARRBUF	       ;BACKGROUND IS STORED IN ARRBUF
	mov DX,03CEH		       ;POINT vga GCR INDEX TO READ MASK
	mov AL,4		       ;
	out DX,AL
	inc DX
	mov AL,0		       ;
PARR1:
	out DX,AL		       ;SET READ MASK TO AL
	mov CL,10		       ;TEN BYTES ARE STORED FROM EACH
PARR2:				       ;PLANE
	mov AH,ES:[si]		       ;READ FROM SCREEN
	mov [DI],AH		       ;STORE IN BUFFER
	inc DI
	mov AH,ES:[si+1]
	mov [DI],AH
	inc DI
	mov AH,ES:[si+2]
	mov [DI],AH
	inc DI
	add si,050H		       ;NEXT LINE DOWN
	dec CL
	jnz PARR2
	mov si,bx		       ;RESTORE si
	inc AL
	cmp AL,4		       ;LAST PLANE DONE?
	jne PARR1		       ;IF NOT, JUMP BACK
	push bx 		       ;save screen address
	mov bl,ArrowColour
	;now print the arrow from the table 'ArrowShape'
	;first the white outline is printed
	mov cl,byte ptr MouseXCoord
	and cl,7		       ;cl='MouseXCoord' & 7
	xor cl,7
	inc cl

	mov edi,0		       ;source pointer in edi
	test ManualAltitude,1
	je @f
	add di,18		       ;point to sideways arrow
@@:
	cmp MouseXCoord,FlipOver
	jge @f
	add di,18		       ;point to reversed arrow
@@:
	mov ch,10		       ;10 rows deep
	mov DX,03CEH		       ;set vga CGR index to bit mask
	mov AL,8
	out DX,AL
	inc DX
PARR3:
	movzx eax,FS:ArrowShape[edi*2]	;get 16 bit line from 'ArrowShape'into ax
	shl eax,cl		       ;line it up
	out DX,AL		       ;load it into the bit mask register
	mov al,ES:[si+2]	       ;dummy read
	mov ES:[si+2],bl		;write white
	shr eax,8
	out DX,AL		       ;set bit mask
	mov al,ES:[si+1]	       ;dummy read
	mov ES:[si+1],bl		;write adjacent byte
	mov al,ah
	out dx,al
	mov al,ES:[si]		     ;dummy read
	mov ES:[si],bl			;write adjacent byte
	inc edi
	add si,050H		       ;next screen line down
	dec ch			       ;decrement row counter
	jnz PARR3		       ;loop 10 times
	xor bl,0fh
	;now the black inner part is printed
	pop si			       ;restore screen address
	add si,80
	mov ch,8		       ;8 rows down
PARR4:
	mov ax,FS:ArrowShape[edi*2]	;get 16 bit line from 'ArrowShape'
	shl eax,cl			;into ax line it up
	out DX,AL			;load it into the bit mask register
	mov al,ES:[si+2]		;dummy read
	mov ES:[si+2],bl		;write black
	shr eax,8
	out DX,AL			;set bit mask
	mov al,ES:[si+1]		;dummy read
	mov ES:[si+1],bl		;write adjacent byte
	mov al,ah
	out dx,al
	mov al,ES:[si]		      ;dummy read
	mov ES:[si],bl		      ;write adjacent byte
	inc edi
	add si,050H		       ;next screen line down
	dec ch			       ;decrement row counter
	jnz PARR4		       ;loop 10 times

	;now print the cross hair cursor
	mov BX,CursorAddress	       ;get address in bx
	dec bx
	mov SI,BX		       ;copy it into si
	;first a 3x10x4 plane background is stored in arrbuf (120 bytes)
	mov DI,offset CursorBuffer     ;BACKGROUND IS STORED IN a buffer
	mov DX,03CEH		       ;POINT vga GCR INDEX TO READ MASK
	mov AL,4		       ;
	out DX,AL
	inc DX
	mov AL,0		       ;
PARR11:
	out DX,AL		       ;SET READ MASK TO AL
	mov CL,10		       ;TEN BYTES ARE STORED FROM EACH
PARR12:				       ;PLANE
	mov AH,ES:[BX]		       ;READ FROM SCREEN
	mov [DI],AH		       ;STORE IN BUFFER
	inc DI
	mov AH,ES:[BX+1]
	mov [DI],AH
	inc DI
	mov AH,ES:[BX+2]
	mov [DI],AH
	inc DI
	add BX,050H		       ;NEXT LINE DOWN
	dec CL
	jnz PARR12
	mov BX,SI		       ;RESTORE BX
	inc AL
	cmp AL,4		       ;LAST PLANE DONE?
	jne PARR11		       ;IF NOT, JUMP BACK
	;now print the cursor from the table 'CursorShape'
	;first the white outline is printed
	mov cl,byte ptr CursorXCoord
	and cl,7		       ;cl='CursorXCoord' & 7
	xor cl,7
	inc cl
	mov edi,0		       ;source pointer in edi
	test ManualAltitude,1
	je @f
	add di,18		       ;point to sideways arrow
@@:
	mov ch,10		       ;10 rows deep
	mov DX,03CEH		       ;set vga CGR index to bit mask
	mov AL,8
	out DX,AL
	inc DX
PARR13:
	movzx eax,FS:CursorShape[edi*2]	;get 16 bit line from 'ArrowShape'into ax
	shl eax,cl		       ;line it up
	out DX,AL		       ;load it into the bit mask register
	mov al,ES:[BX+2]	       ;dummy read
	mov byte PTR ES:[BX+2],00H	;write white
	shr eax,8
	out DX,AL		       ;set bit mask
	mov al,ES:[BX+1]	       ;dummy read
	mov byte PTR ES:[BX+1],00H     ;write adjacent byte
	mov al,ah
	out dx,al
	mov al,ES:[BX]	       ;dummy read
	mov byte PTR ES:[BX],00H     ;write adjacent byte
	inc edi
	add BX,050H		       ;next screen line down
	dec ch			       ;decrement row counter
	jnz PARR13		       ;loop 10 times

	;now the black inner part is printed

	mov BX,SI		       ;restore screen address from si
	add bx,80
	mov ch,8		       ;8 rows down
PARR14:
	mov ax,FS:CursorShape[edi*2]	;get 16 bit line from 'ArrowShape'into ax
	shl eax,cl		       ;line it up
	out DX,AL		       ;load it into the bit mask register
	mov al,ES:[BX+2]	       ;dummy read
	mov byte PTR ES:[BX+2],0fH	;write black
	shr eax,8
	out DX,AL		       ;set bit mask
	mov al,ES:[BX+1]	       ;dummy read
	mov byte PTR ES:[BX+1],0fH     ;write adjacent byte
	mov al,ah
	out dx,al
	mov al,ES:[BX]	       ;dummy read
	mov byte PTR ES:[BX],0fH     ;write adjacent byte
	inc edi
	add BX,050H		       ;next screen line down
	dec ch			       ;decrement row counter
	jnz PARR14		       ;loop 10 times
 PARRF:
	;SIGNAL ARROW DRAWN
	mov MouseShowing,1
	RET


bgtext: ;entry point for bigger status line text
	;prints string from [si] to screen [bx]
	push SI
	mov DX,03CEH
	mov AL,8		       ;POINT VGA INDEX TO BIT MASK
	out DX,AL
	cmp byte PTR [SI],0FFH	       ;IF THE FIRST byte OF ANNOTATION
	jne @f			       ;IS 0FFH, EXIT
	pop SI
	RET
@@:
	;First the length of the string is found in CH
	;so that a background may be blanked out
	mov CH,1		       ;Initailize total with 1
@@:
	mov AL,[SI]		       ;get character from string
	cmp AL,0FFH		       ;end of string?
	je @f			       ;if so, end calculation
	sub al,20h		       ;ascii adjust
	cmp al,5fh
	jbe BadChar
	mov al,'?'
BadChar:
	mov AH,0		       ;get char*12 in AX
	shl AX,2		       ;start of font in DI
	mov DI,offset FontC	       ;find offset of character
	add DI,AX		       ;in DI
	shl ax,1
	add di,ax
	mov AL,FS:[DI+11]	       ;get x size (0-9) from bits 0-3
	and AL,0fH		       ;from last byte of font
	add CH,AL		       ;add this to total in CH
	inc SI			       ;increase character pointer
	JMP @b			       ;loop round
ForceLength:
	mov DX,03CEH
	mov AL,8		       ;POINT VGA INDEX TO BIT MASK
	out DX,AL
	push si
@@:
	;now print int(ch/8) 8x14 pixel blocks
	push BX 		       ;save screen address
	inc DX			       ;point to vga data register
	mov AL,0FFH		       ;bit mask is 11111111b
	out DX,AL		       ;set it
	test CH,0F8H		       ;if length<8 pixels, jump out
	jz PRNB18
PRANB13:
	mov AH,14		       ;background is 14 lines down
@@:
	mov AL,ES:[BX]		       ;dummy read
	mov al,TextColour	       ;get colour
	shr al,4		       ;background colour
	mov ES:[BX],al		       ;write white line
	add BX,050H		       ;next screen line down
	dec AH			       ;line counter
	jnz @b			       ;loop 14 times
	SUB BX,1119		       ;restore screen address and advance it
	SUB CH,08H		       ;decrease length by 8
	test CH,0F8H		       ;is length still>7?
	jnz PRANB13		       ;if so, loop back
PRNB18:
	;now print the remaining 0-7 pixels
	mov CL,CH		       ;remaining length in CL
	Xor CL,07H		       ;invert it
	inc CL			       ;plus one
	mov AL,0FFH		       ;bit mask in al
	shl AL,CL		       ;shift left by CL
	out DX,AL		       ;set bit mask
	mov AH,14		       ;14 lines down
@@:
	mov AL,ES:[BX]		       ;dummy read
	mov al,TextColour		       ;get colour
	shr al,4		       ;background colour
	mov ES:[BX],al		       ;write white row
	add BX,050H		       ;next screen line down
	dec AH			       ;count
	jnz @b			       ;loop 14 times
	pop BX			       ;restore screen address
	pop SI			       ;restore string pointer
	mov CL,1		       ;shift offset in CL
	out DX,AL
	add BX,050H		       ;add one row to screen address

PRANT11:
	;now the text is printed within the block
	mov DX,03CFH
	mov AL,[SI]		       ;get character from string
	cmp AL,0FFH		       ;if it is 0FFh,
	je PRANTFi		       ;jump to finish
	;check if char is in bounds
	cmp al,127
	ja NotPrintable
	cmp al,' '
	jae Printable

NotPrintable:
	mov ah,al
	and ah,0f0h
	cmp ah,0e0h		       ;0exh=colour control
	jne NotColCon
	mov ah,LightFuncText
	cmp al,0e0h
	je @f
	mov ah,DarkFuncText
	cmp al,0efh
	je @f
	and al,0fh
	and ah,0f0h
	or ah,al
@@:
	mov TextColour,al
NotColCon:
	cmp ah,0b0h		       ;0bxh=tab control
	jne @f
	mov bx,WSPointer
	and al,0fh
	mov ah,al
	shl al,2
	add al,ah
	mov ah,0
	add bx,ax
	mov cl,1
@@:
	inc si
	jmp prant11

Printable:
	sub al,20h		       ;ascii adjust
	cmp al,5fh
	jbe @f
	mov al,0
@@:
	mov AH,0		       ;get character*12 in AX
	shl AX,2
	mov DI,offset FontC	       ;DI=start of small font
	add DI,AX		       ;DI=offset of character in font
	shl ax,1
	add di,ax
	mov CH,11		       ;characters are 11 rows down
	push BX 		       ;save screen address
	test byte ptr fs:[di+11],080h	       ;decender?
	je @f
	add bx,160		       ;if so, add 2 lines
@@:
	mov AH,FS:[DI]		       ;get line from font
	mov AL,00		       ;form shift register from AX
	shr AX,CL		       ;shift right by x offset
	XCHG AL,AH		       ;swop bytes
	out DX,AL		       ;output high byte as bit mask
	mov DL,ES:[BX]		       ;dummy read to DL
	mov dl,TextColour	       ;get colour
	and dl,0fh		       ;foreground colour
	mov ES:[BX],dl		       ;write black pixels
	mov DL,0CFH		       ;restore vga address in DX
	mov AL,AH		       ;get second byte in AL
	out DX,AL		       ;write bit mask
	mov DL,ES:[BX+1]	       ;dummy read to DL
	mov dl,TextColour		       ;get colour
	and dl,0fh		       ;foreground colour
	mov ES:[BX+1],dl	       ;write black pixels
	mov DL,0CFH		       ;restore DL
	inc DI			       ;increase font pointer
	add BX,050H		       ;screen address down one row
	dec CH			       ;row counter
	jnz @b			       ;loop back 11 times

	pop BX			       ;restore screen address
	mov AL,FS:[DI]		       ;get character width from last font
	and al,0fh		       ;width is bits 0-3
	add CL,AL		       ;add this to shift offset
	cmp cl,08		       ;if offset>8, subract 8
	jb @f
	sub cl,8
	inc bx			       ;and increment the screen address
@@:
	cmp cl,08		       ;cl may have gained more than
	jb @f			       ;8 so do it again
	sub cl,8
	inc bx			       ;increment the screen address
@@:
	inc SI			       ;increment string pointer
	JMP PRANT11		       ;loop back

PRANTFi: RET			       ;finished here


RemoveArrow: ;THIS RESTORES THE BACKGROUND BEHIND THE ARROW
	;test InitRedraw,02H
	;jne RARRF

	mov AL,8		       ;first set bit mask to 0ffh
	mov AH,0FFH
	call SETGCR

	mov BX,CursorAddress	       ;get address to print at
	dec bx
	mov DX,03CEH
	mov AL,05
	out DX,AL
	inc DX
	mov AL,00H		       ;SET WRITE MODE 0
	out DX,AL

	mov DX,03C4H
	mov AL,02
	out DX,AL		       ;POINT INDEX TO MAP MASK
	inc DX
	mov DI,BX
	mov SI,offset CursorBuffer     ;address of background store buffer
	mov AL,01H		       ;plane number in al
RARR11:
	out DX,AL		       ;set plane number
	mov CL,10
RARR12:
	mov AH,ES:[BX]
	mov AH,[SI]
	mov ES:[BX],AH
	inc SI
	mov AH,ES:[BX+1]
	mov AH,[SI]
	mov ES:[BX+1],AH
	inc SI
	mov AH,ES:[BX+2]
	mov AH,[SI]
	mov ES:[BX+2],AH
	add BX,050H
	inc SI
	dec CL
	jnz RARR12
	mov BX,DI
	shl AL,1
	cmp AL,010H
	jne RARR11
	mov DX,03CEH
	mov AL,05
	out DX,AL
	inc DX

	mov BX,RemoveAddress	       ;get address to print at
	mov DX,03C4H
	mov AL,02
	out DX,AL		       ;POINT INDEX TO MAP MASK
	inc DX
	mov DI,BX
	mov SI,offset ARRBUF	       ;address of background store buffer
	mov AL,01H		       ;plane number in al
RARR1:
	out DX,AL		       ;set plane number
	mov CL,10
RARR2:
	mov AH,ES:[BX]
	mov AH,[SI]
	mov ES:[BX],AH
	inc SI
	mov AH,ES:[BX+1]
	mov AH,[SI]
	mov ES:[BX+1],AH
	inc SI
	mov AH,ES:[BX+2]
	mov AH,[SI]
	mov ES:[BX+2],AH
	add BX,050H
	inc SI
	dec CL
	jnz RARR2
	mov BX,DI
	shl AL,1
	cmp AL,010H
	jne RARR1
	mov DX,03CEH
	mov AL,05
	out DX,AL
	inc DX
	mov AL,02H		       ;SET WRITE MODE 2
	out DX,AL
	mov DX,03C4H
	mov AL,02
	out DX,AL		       ;POINT INDEX TO MAP MASK
	inc DX
	mov AL,0FH
	out DX,AL		       ;RESTORE MAP MASK TO ALL PLANES
RARRF:
	mov MouseShowing,0
	RET

EXTIME: ;THIS EXPANDS THE TIME IN AX INTO ASCII IN ETBUFF
	mov SI,offset ETBuff	;build text in 'ETBuff'
	mov bx,ax
	and ax,0f0fh
	and bx,0f0f0h
	shr bx,4
	add ax,3030h
	add bx,3030h
	xchg al,bh
	mov [si],bx
	mov [si+3],ax
	mov byte ptr [si+2],':'
	mov byte PTR [SI+5],0FFH       ;STRING TERMINATOR
	RET


PrintStatusBar:
	call psblank		       ;blank out top 28 lines with colour 7
	call psinit		       ;set up status line titles and boxes
	call psgrsc		       ;palette bar
	call PaletteDimple
	call StatusRange
	call StatusSpeed
	call StatusAngle
	call StatusLayback
	call StatusScope
	call StatusCourse
	call StatusSounding
	call StatusGeometry
	call StatusMode
	call StatusZoomPan
	call StatusTime
	;call StatusDate
	call StatusPrntMode
	;call StatusPrntType
	call pdiple			;annotation and info dimples
	call zdiple			;zoom dimple
	call patext
	RET

PrintBanner:
	mov di,offset BannerMessage
	call CopyMessage
	mov TextColour,0f0h
	call scrnad
	IF (PSEA+DOS) EQ 2
	add bx,36822
	ELSEIF REPLAY
	add bx,36825
	ELSEIF DOS
	add bx,36829
	ELSE
	add bx,36827
	ENDIF

	mov cl,1
	call prant11
	ret

PrintRegValue:
	movzx bx,RegisterNumber
	shl bx,1
	mov ax,fs:RegisterTable[bx]
	mov word ptr InfoMessage,ax
	shl bx,1
	mov eax,ErrorEAX[bx]
	mov si,(offset InfoMessage+2)
	mov byte ptr [si],':'
	inc si
PrintRegEax:
	mov cl,8
PrintReg1:
	rol eax,4
	;rol al,1
	mov bl,al
	and bl,0fh
	;and bl,1
	add bl,30h
	cmp bl,39h
	jbe @f
	add bl,7
@@:
	mov [si],bl
	inc si
	dec cl
	jnz PrintReg1
	mov byte ptr [si],0ffh
	jmp pitext

patext: ;prints the text in 'anbuff' in the annotation box
	;first print a clear background
	mov al,LightStatText
	mov TextColour,al
	call scrnad
	add bx,618
	mov si,offset anbuff
	mov ch,060h
	call ForceLength
	ret

pitext: ;prints the text in 'InfoMessage' in the message box
	;first print a clear background
	mov al,LightStatText
	mov TextColour,al
	call scrnad
	add bx,2618
	mov si,offset InfoMessage
	mov ch,060h
	call ForceLength
	ret

petext:
	;prints the text at fs:[di] in the message box
	mov al,LightStatText
	mov TextColour,al
	call scrnad
	add bx,2618
	call CopyMessage
	mov ch,060h
	call ForceLength
	ret

PrintErrorMsg: ;prints the message at [si] in the message box
	;first print a clear background
	push si 			;save text pointer
	mov di,offset tspace
	call CopyMessage
	mov al,LightStatText
	mov TextColour,al
	call scrnad
	add bx,2618
	call bgtext

	pop di				;restore text pointer
	mov al,24
	mov ErrorFade,al
	jmp PrntError2

PrntError1:
	mov ErrorFade,al
	cmp al,08h
	ja @f
	dec al
	xor al,07h		       ;invert colour
	and al,0feh		       ;go only through greys
	mov ah,WindowBackground	       ;
	shl ah,4
	add al,ah
	inc al
	mov TextColour,al
PrntError2:
	push di
	call scrnad
	add bx,2618
	call CopyMessage
	call bgtext			;print the error message
	pop di
@@:
	mov cx,0
@@:
	loop @b
@@:
	loop @b
@@:
	loop @b
	mov al,ErrorFade
	dec al
	jnz PrntError1
	mov di,offset tspace
	call CopyMessage
	mov al,LightStatText
	mov TextColour,al
	call scrnad
	add bx,2618
	call bgtext
	ret

pdiple: ;prints a dimple for the annotation box
	call scrnad
	add bx,457
	mov si,bx
	mov bx,120ch
	call PrintDimple
	call scrnad
	add bx,2457
	mov si,bx
	mov bx,120ch
	call PrintDimple
	ret

PaletteDimple:
	call ScrnAd
	add bx,2268
	mov si,bx
	mov bx,1401h
	call PrintDimple
	ret

zdiple: ;prints a dimple for the pan\zoom box
	call scrnad
	add bx,981
	mov si,bx
	mov bx,0d08h		       ;bh=height  bl=length

PrintDimple:
	mov dx,03ceh
	mov al,8		       ;point vga index
	out dx,al		       ;at bit mask
	inc dx
	;first print left hand side
	mov di,si		       ;save screen address
	mov al,03h
	out dx,al		       ;set bit mask to 00000011
	mov cl,bh
	mov al,WindowFrameDark	       ;colour
@@:
	mov ah,es:[si]
	mov es:[si],al
	add si,050h
	dec cl
	jnz @b

	mov al,1
	out dx,al
	mov ah,es:[si-80]
	mov ah,WindowFrameLight
	mov byte ptr es:[si-80],ah	;colour

	mov si,di
	movzx cx,bl
	inc cx
	add si,cx
	mov di,si

	;now print right hand side
	mov al,0c0h
	out dx,al		       ;set bit mask to 11000000
	mov cl,bh
	mov al,WindowFrameLight	       ;colour
@@:
	mov ah,es:[si]
	mov es:[si],al
	add si,050h
	dec cl
	jnz @b

	mov si,di
	mov ah,es:[si]
	mov ah,WindowFrameDark
	mov byte ptr es:[si],ah
	mov al,80h
	out dx,al
	mov ah,es:[si+50h]
	mov ah,WindowFrameDark
	mov byte ptr es:[si+50h],ah
	mov al,0ffh
	out dx,al

	mov al,WindowFrameLight
	mov ah,WindowFrameDark
	sub bh,2
	mov cl,bh
	shl cl,2
	add cl,bh
	mov ch,0
	shl cx,4
	add di,cx
@@:
	dec si
	dec di
	mov es:[si],ah
	mov es:[si+80],ah
	mov es:[di],al
	mov es:[di+80],al
	dec bl
	jnz @b
	ret


	;*STATUS LINE ROUTINES*



StatusRange:
	;this prints the towfish range and type
	mov di,offset PSRMSG	       ;message list
	movzx ax,RangeNumber	       ;message pointer is range x 5
	and al,0fh
	add di,ax
	shl ax,2
	add di,ax
	mov al,LightStatText
	mov TextColour,al
	call scrnad
	add bx,2917
	call CopyMessage
	call bgtext

	call scrnad		       ;get screen address in bx
	add bx,912		       ;offset in screen of message
	mov al,RangeNumber
	mov di,offset typemsg
	test al,80h
	je @f
	add di,3
@@:
	and al,0fh
	cmp al,10		       ;is range a valid HF range
	jne @f
	mov di,offset BlankType	       ;if not, blank type
@@:
	call CopyMessage
	call bgtext
	ret

StatusAltitude:
	;this prints the altitude above the seabed in metres
	mov si,offset testmsg
	mov word ptr [si+4],0ff20h	;terminator
	mov AL,Altitude		       ;Altitude in .08m(HF) or .16m(LF)
	cmp al,0fbh		       ;if altitude is at 20m (40m if LF)
	jae MaxAltitude		       ;print 'MAX' instead
	cmp al,0
	je NoAltitude
	mov ah,0		       ;Altitude in ax
	shl ax,4		       ;multilply by 16
	mov bl,100
	div bl
	;al is now Altitude in metres
	;ah contains extra centimetres
	mov bl,ah
	aam
	add ax,3030h
	cmp ah,'0'		       ;kill leading zero
	je @f
	mov [si],ah		       ;most sig. fig.
	inc si
@@:
	mov [si],al		       ;least sig. fig.
	mov al,bl		       ;get centimetres
	aam
	add ah,30h
	mov byte ptr [si+1],'.'        ;decimal point
	mov [si+2],ah
	mov byte ptr [si+3],'m'        ;'m' for metres
	mov si,offset testmsg
@@:
	call scrnad
	add bx,2912		       ;position in screen
	mov al,LightStatText
	mov TextColour,al
	mov ch,40
	call ForceLength	       ;print big text
	ret

MaxAltitude:
	mov dword ptr [si],' XAM'
	mov word ptr [si+4],0ff60h
	jmp @b

NoAltitude:
	mov dword ptr [si],' a/n'
	mov word ptr [si+4],0ff60h
	jmp @b

blhgt:	;blanks out the altitude
	mov si,offset testmsg			 ;blank altitude
	mov word ptr [si],'  '
	mov word ptr [si+2],'| '
	mov word ptr [si+4],0ff7ch
	jmp @b

HELPM:	;HELP PAGES
	call RemoveArrow
	test WindowFlag,4	       ;is help already active?
	jne @f			       ;if not, first turn off
	call SwapWindow		       ;all other menus
@@:
	mov WindowFlag,4	       ;signal help on
	cmp helpc,6		       ;WAS THAT THE LAST PAGE?
	je HLPFIN		       ;IF SO, RESTORE SCREEN
	mov FreezeMode,1	       ;otherwise set freeze mode
	call ClearWindow	       ;and clear window
	;find the address of the help text
	mov bl,helpc
	mov bh,0
	shl bx,1
	mov di,HelpTextTable[bx]       ;in di
	call PrintMenu		       ;print page of text
	inc helpc		       ;increment help page number
	call PrintArrow
	jmp KeyDone		       ;finished


HLPFIN: ;RUN WHEN HELP IS FINISHED
	call killws
	jmp KeyDone

StatusPage:
	;this brings up the system status window
	call RemoveArrow
	call SwapWindow		       ;kill other windows
	mov WindowFlag,040H	       ;Status Page ACTIVE
	mov CHARC,0		       ;RESET COLUMB COUNT
	call ClearWindow
	mov FreezeMode,1	       ;SET FREEZE MODE
	mov DI,offset StatPageText	;SET UP SOURCE TEXT POINTER
	call PrintMenu		       ;print function menu
	call PrintArrow
	call StatusSystem
	jmp KeyDone		       ;end

StatusSystem:
	;buffer size
	mov si,offset testmsg
	mov ax,BufferSize
	call PrintDecimal
	mov byte ptr [si],0ffh
	call scrnad
	add bx,14338
	mov al,LightStatText
	mov TextColour,al
	mov ch,38
	mov si,offset testmsg
	call ForceLength
	IF 0
	;coax power on/off
	mov si,offset testmsg
	mov byte ptr [si],'O'
	mov ax,'ff'
	test CoaxPower,8
	je @f
	mov ax,' n'
@@:
	mov [si+1],ax
	mov byte ptr [si+3],0ffh
	call scrnad
	add bx,15463
	mov al,LightStatText
	mov TextColour,al
	mov ch,38
	call ForceLength
	;drive voltage
	mov si,offset testmsg
	mov al,0
	test CoaxPower,8
	je StatSys1
	mov al,20
	test CoaxBoardType,1
	je StatSys1
	mov ah,CoaxDrive
	mov al,15
@@:
	add al,5
	shr ah,1
	jc @b
StatSys1:
	aam
	xchg al,ah
	add ax,'00'
	mov [si],ax
	mov word ptr [si+2],0ff76h
	call scrnad
	add bx,16583
	mov ch,38
	call ForceLength
	;regulator input
	mov si,offset testmsg
	mov eax,0ff612f6eh
	mov [si],eax
	test SonarIsOn,1
	je @f
	mov al,RegulatorVoltage
	xor al,07fh
	mov AH,0		       ;167 mV per unit in ax
	mov bx,167
	mul bx
	add ax,7130		       ;+7.13 volts offset
	mov bx,1000
	div bx
	aam
	add ax,3030h
	mov [si],ah
	mov [si+1],al
	mov byte ptr [si+2],'v'
	mov byte ptr [si+3],0ffh
@@:
	call scrnad
	add bx,17700
	mov ch,38
	call ForceLength
	;regulator output
	mov si,offset testmsg
	mov eax,0ff612f6eh
	mov [si],eax
	test CoaxPower,8
	je @f
	mov al,BatteryVoltage
	xor al,07fh
	mov AH,0		       ;31 mV per unit in ax
	mov BX,AX		       ;1
	shl ax,5		       ;32
	sub ax,bx		       ;31
	add ax,4000		       ;+4 volts offset
	mov BL,100
	div bl
	aam
	add ax,3030h
	mov [si],ah
	mov byte ptr [si+1],'.'
	mov [si+2],al
	mov byte ptr [si+3],'v'
	mov byte ptr [si+4],0ffh
@@:
	call scrnad
	add bx,18822
	mov ch,38
	call ForceLength
	;battery voltage
	mov si,offset testmsg
	mov eax,0ff612f6eh
	mov [si],eax
	test CoaxPower,8
	jne @f
	test SonarIsOn,1
	je @f
	mov al,BatteryVoltage
	xor al,07fh
	mov AH,0		       ;31 mV per unit in ax
	mov BX,AX		       ;1
	shl ax,5		       ;32
	sub ax,bx		       ;31
	add ax,4000		       ;+4 volts offset
	mov BL,100
	div bl
	aam
	add ax,3030h
	mov [si],ah
	mov byte ptr [si+1],'.'
	mov [si+2],al
	mov byte ptr [si+3],'v'
	mov byte ptr [si+4],0ffh
@@:
	call scrnad
	add bx,19941
	mov ch,38
	call ForceLength
	ENDIF
	ret

FMENU:	;BRINGS UP THE FUNCTION MENU
	call RemoveArrow
	call SwapWindow		       ;kill other windows
	mov WindowFlag,01H	       ;FUNCMENU ACTIVE
	mov CHARC,0		       ;RESET COLUMB COUNT
	call ClearWindow
	mov FreezeMode,1	       ;SET FREEZE MODE
	mov DI,offset FuncMenuText	       ;SET UP SOURCE TEXT POINTER
	call PrintMenu		       ;print function menu
	call PrintArrow
	jmp KeyDone		       ;end

StoreCMOS3:  ;write DisplayFlags to byte 3 of CMOS
	mov al,3
	out 70h,al
	mov al,DisplayFlags
	IFE PSEA
	and al,07fh			;make sure default is monochrome
	ENDIF
	out 71h,al
	ret

StoreCMOS5: ;writes 50*(BaudRate-1)+10*MouseRate+PrinterNumber
	    ;to byte 5 of the CMOS
	mov al,BaudRate
	dec al
	mov ah,50
	mul ah
	mov bl,al
	mov al,MouseRate
	mov ah,10
	mul ah
	mov ah,PrinterNumber
	add ah,al
	add ah,bl
	mov al,5
	out 70h,al
	nop
	nop
	mov al,ah
	out 71h,al
	ret


FunctionCancel: ;CANCELS THE FUNCTION MENU
	call StoreCMOS3
	call StatusTime		       ;PRINT TIME (might be changed)
	call killws		       ;remove window
	mov FuncZCount,0
	mov FuncUCount,0
	JMP FUNS2		       ;CLEAR ANNOTATION BOX

prmcel: ;CANCELS THE printer MENU
	call killws		       ;remove window
	call StatusPrntMode
	;call StatusPrntType
	JMP FUNS2		       ;CLEAR ANNOTATION BOX

PNavMenu:	;BRINGS UP THE nav data MENU
	test WindowFlag,020H	       ;IS nav menu ACTIVE?
	je @F
	mov si,offset ErrorMsg3        ;'invalid key'
	call Rebuke		       ;Rebuke IF SO
	jmp KeyDone
@@:
	call RemoveArrow
	call SwapWindow		       ;kill other windows
	mov WindowFlag,020H	       ;nav menu ACTIVE
	mov CHARC,0		       ;RESET COLUMB COUNT
	call ClearWindow
	mov FreezeMode,1	       ;SET FREEZE MODE
	mov DI,offset NavMenuText      ;set UP SOURCE TEXT POINTER
	call PrintMenu		       ;print function menu
	;now display the last fix from the calc posn button
	mov ebx,LatitudeFix
	mov si,offset InfoMessage
	mov ch,0
	call WriteNavMinutes
	mov al,LightStatText
	mov TextColour,al
	call scrnad
	add bx,33462
	mov si,offset InfoMessage
	mov ch,050h
	call ForceLength

	mov ebx,LongitudeFix
	mov si,offset InfoMessage
	mov ch,1
	call WriteNavMinutes
	mov al,LightStatText
	mov TextColour,al
	call scrnad
	add bx,33473
	mov si,offset InfoMessage
	mov ch,050h
	call ForceLength
	call PrintArrow
	jmp KeyDone		       ;end

PrintMenu: ;prints a menu from source text at [DI]
	mov al,DarkStatText
	mov TextColour,al
	mov WindowTextPointer,DI
	call SCRNAD
	add BX,9927		       ;BX=TOP OF WINDOW
	mov WSPointer,BX     ;SET UP DESTINATION POINTER

MENULP:
	;the text is copied into testmsg
	;then printed one line at a time
	mov di,offset testmsg	       ;destination buffer
	mov SI,WindowTextPointer       ;GET SOURCE POINTER
PMenu1:
	mov AL,FS:[SI]		       ;GET CHARACTER
	inc si			       ;increment source
	;sort out control characters
	cmp AL,0FEH		       ;0feh=END OF PAGE
	je FMNFIN
	cmp AL,0FFH		       ;0ffh=END OF LINE
	je MARRET
	cmp al,0cdh		       ;0cdh=altitude alarm enable/disable
	je AltAlarmCont
	cmp al,0ceh		       ;0ceh=altitude adjust
	je AltAdjust
	mov ah,al
	cmp ah,0cfh		       ;0cfh=coax power on/off
	je OnOff
	and ah,0f0h
	cmp ah,0c0h		       ;0cxh=hide/show control
	je HideShow
	cmp ah,0d0h		       ;0dxh=baud/nav arrow control
	je BulletPoint
	;character is in al
@@:
	mov [di],al		       ;store character in buffer
	inc di			       ;increment destination
	JMP PMenu1			       ;LOOP BACK

BulletPoint:
	test al,08h
	jne NavArrow
	and al,07h
	cmp al,BaudRate
	mov al,'|'			;|=space
	jne @b
	mov al,'&'			;&=mini arrow
	jmp @b

NavArrow:
	and al,07h
	mov ah,DisplayFlags
	shr ah,2
	and ah,5
	cmp al,ah
	mov al,'|'
	jne @b
	mov al,'&'			;&=mini arrow
	jmp @b


HideShow:
	and al,07h
	mov cl,al
	mov al,1
	shl al,cl
	test al,DisplayFlags
	mov eax,'ediH'
	jnz @f
	mov eax,'wohS'
@@:
	mov [di],eax
	add di,4
	jmp PMenu1


OnOff:
	mov cl,CoaxPower
	test cl,8
	je @f
	mov word ptr [di],'po'
	add di,2
	jmp PMenu1

@@:
	mov word ptr [di],'ra'
	mov byte ptr [di+2],'t'
	add di,3
	jmp PMenu1

AltAlarmCont:
	test AlarmControl,2
	je @f
	;alarm is active
	mov word ptr [di],'iD'
	mov byte ptr [di+2],'s'
	add di,3
	jmp PMenu1
@@:
	mov word ptr [di],'nE'
	add di,2
	jmp PMenu1

AltAdjust:
	mov ax,'ff'
	test ManualAltitude,1
	jne @f
	mov ax,' n'
@@:
	mov [di],ax
	add di,2
	jmp PMenu1

MARRET:
	;this prints the line of text in testmsg
	mov byte ptr [di],0ffh
	mov WindowTextPointer,si       ;store updated source pointer
	mov bx,WSPointer     ;get screen address
	push bx
	mov si,offset testmsg	       ;reset source pointer
	mov cl,1		       ;shift offset for prant11
	call prant11		       ;print in big font
	pop bx			       ;restore screen address
	add bx,1120		       ;next line down
	mov WSPointer,bx     ;store it
	JMP menulp

FMNFIN:
	ret

killws: ;this turns off the lower window
	;it is called if a window function is terminated
	call SwapWindow		       ;kill all menus
	call ClearWindow	       ;clear window
	mov al,SavedFreeze
	mov FreezeMode,al	       ;turn off freeze mode
	test al,1			;was freeze on?
	jmp @f
	mov NewCurZoom,2
	mov RedrawMapLine,64
	mov ax,ScreenLineMap[128]
	mov RLINE,AX
	mov InitRedraw,02H
	call SCRNAD
	add BX,9200
	call StartR1
	ret
@@:
	;start a full redraw
	mov InitRedraw,1
	mov NewCurZoom,0
	mov InitRedraw,01H	       ;start REDRAW
	ret

SwapWindow: ;this clears the lower window to swap from one window
	;to another
	cmp WindowFlag,0	       ;any windows
	jne @f
	mov al,FreezeMode
	mov SavedFreeze,al
@@:
	mov WindowFlag,00h	       ;no windows active
	mov al,00
	mov helpc,al		       ;reset help page count
	mov dirflg,al		       ;reset directory counts
	mov dirnum,al
	ret

bigrng: ;this prints the current range in large letters
	mov FreezeMode,1	       ;set freeze mode
	mov HideMouse,1
	call RemoveArrow
	call ClearWindow	       ;clear window
	mov si,offset bigmsg
	movzx ax,RangeNumber	       ;multiply range by 3
	and al,0fh
	add si,ax
	shl ax,1
	add si,ax
	;SI now points to range string eg `050' or `100'
	call scrnad		       ;get top of screen in bx
	add bx,13445		       ;top of window in bx
	mov DX,03ceh
	mov AL,8
	out DX,AL		       ;POINT INDEX TO bit MASK
	inc DX

	cmp byte ptr fs:[si],'0'       ;is first char '0'?
	jz @f			       ;if so, don't print it
	call pbchar		       ;print big character
@@:
	inc si			       ;increase string pointer
	add bx,24
	call pbchar
	inc si			       ;increase string pointer
	add bx,24
	call pbchar
	mov si,offset NewRangeMsg
	;call SoundChime
	mov InitRedraw,1
	mov WindowFlag,00h
	mov FreezeMode,00h
	ret


pbchar: ;prints a large character [si] at bx
	;each character is composed of a 11x16 block of
	;dots, each dot is drawn in a 16x16 block of pixels
	mov al,fs:[si]		       ;get character in al
	sub al,30h		       ;get its value
	push si 		       ;save string pointer
	mov ah,0		       ;zero ah
	shl ax,5		       ;times by 32 bytes per char
	mov di,offset FontD	       ;big fonts table
	add di,ax		       ;di is pointer to font
pbchrm:
	push bx 		       ;save screen address
	mov cl,16		       ;16 rows
pbchr1:
	mov ax,fs:[di]		       ;get row from font in ax
	shl eax,16		       ;store font line in bits 31-20
	mov ch,12		       ;12 dots across
pbchr2:
	shl eax,1		       ;shift font line
	jnc pbchr3		       ;if no bit set, skip
	mov ah,16		       ;16x16 box
	mov si,offset dotpic	       ;dot graphic
@@:
	mov al,es:[bx]		       ;dummy read
	mov al,fs:[si]		       ;get dot font byte
	out dx,al		       ;set bit mask
	mov byte ptr es:[bx],0	       ;write colour black
	inc si
	inc bx
	mov al,es:[bx]		       ;dummy read
	mov al,fs:[si]		       ;get dot font byte
	out dx,al		       ;set bit mask
	mov byte ptr es:[bx],0	       ;write black
	inc si
	add bx,79		       ;next row down
	dec ah
	jnz @b
	sub bx,1280		       ;put bx back to top row of char
pbchr3:
	add bx,2
	dec ch
	jnz pbchr2
	add bx,1256		       ;point bx to start of next row
	add di,2
	dec cl
	jnz pbchr1
	pop bx			       ;restore screen address
	pop si
	ret

AlterAltitude:
	;first check disk
	cmp StorageMode,01H	       ;is it in play mode?
	je @f			       ;error if so
	mov si,offset ErrorMsg15       ;'wrong mode'
	call Rebuke
	stc
	ret
@@:
	call VerifyForRead	       ;make sure a disk is in
	jnc @f
	mov si,offset ErrorMsg7        ;'no disk'
	call Rebuke
	stc
	ret
@@:
	call GetDistance		;get distance in ax 1/10th metres
	;convert to unit of altitude by *5 then /8
	mov dx,ax
	shl ax,2
	add ax,dx
	shr ax,3
	mov dx,ax			;save in dx and si
	mov si,ax
	;see if this altitude is too much
	cmp dh,0
	je @f
	mov si,offset ErrorMsg43
	call Rebuke
@@:
	mov bx,MouseYCoord		;get y co-ordinate
	add bx,5
	shl bx,1
	mov ax,ScreenLineMap[bx]
	;sub ax,1
	and ax,BufferLimit
	mov bp,ax		       ;save the line number in bp
	;alter altitude at centre line
	shl ax,3		       ;calculate segment
	add ax,038h
	mov gs,ax
	mov eax,gs:[0f9ch]	       ;get the cluster number from the line
	;now check if this cluster is contained in the current record
	;first is it before the first cluster?
	cmp StartCluster,eax	       ;if it is before the start, abort
	jae ChangeAltError
	cmp StopCluster,eax	       ;stop cluster only matters in
	jbe ChangeAltError	       ;Play mode
	mov byte ptr gs:[0f84h],dl
	;find the altitude at bp+16
	mov ax,bp
	add ax,16
	and ax,BufferLimit
	shl ax,3		       ;calculate segment
	add ax,038h
	mov gs,ax
	mov bl,0
	mov bh,byte ptr gs:[0f84h]	;get upper altitude*128 in bx
	shr bx,1
	shl dx,7
	sub bx,dx			;difference in bx
	sar bx,4			;difference/line in bx
	mov cx,15
@@:
	inc bp
	and bp,BufferLimit
	mov ax,bp
	shl ax,3		       ;calculate segment
	add ax,038h
	mov gs,ax
	shl dx,1
	mov byte ptr gs:[0f84h],dh	;alter altitude
	shr dx,1
	add dx,bx
	loop @b

	sub bp,15			;restore bp to center line
	and bp,BufferLimit
	;now alter altitudes below marker
	mov dx,si
	;find the altitude at bp-16
	mov ax,bp
	sub ax,16
	and ax,BufferLimit
	shl ax,3		       ;calculate segment
	add ax,038h
	mov gs,ax
	mov bl,0
	mov bh,byte ptr gs:[0f84h]	;get lower altitude*128 in bx
	shr bx,1
	shl dx,7
	sub bx,dx			;difference in bx
	sar bx,4			;difference/line in bx
	mov cx,15
@@:
	dec bp
	and bp,BufferLimit
	mov ax,bp
	shl ax,3		       ;calculate segment
	add ax,038h
	mov gs,ax
	shl dx,1
	mov byte ptr gs:[0f84h],dh	;alter altitude
	shr dx,1
	add dx,bx
	loop @b
	;write the altered sectors
	mov edx,gs:[0f9ch]		;cluster number
	mov di,bp			;segment
	call WriteNewAlt
	clc
	ret

ChangeAltError:
	mov si,offset ErrorMsg6 	;'wrong record'
	call Rebuke
	stc
	ret


FUNCKY:	;SORTS out THE FUNCTION menu SELECTIONS
	cmp al,'G'
	je FuncToggleAdjust		;G=toggle manual al
	;je StatusPage
	cmp al,'V'		       ;V=toggle event marks
	je FuncToggleEvent
	cmp AL,'S'		       ;S=sequence
	je FuncSequence
	cmp al,'R'		       ;R=repeat
	je FuncSequence
	cmp al,'B'		       ;B=Altitude (altitude) boxes
	je FuncToggleAlt
	cmp al,'A'		       ;A=annotation
	je FuncToggleAnno
	cmp al,'J'		       ;J=range lines
	je FuncToggleRange
	cmp al,'Y'		       ;Y=set year
	je FuncSetYear
	cmp al,'M'		       ;M=set month
	je FuncSetMonth
	cmp al,'D'		       ;D=set day
	je FuncSetDay
	cmp al,'H'		       ;H=set hour
	je FuncSetHour
	cmp al,'T'		       ;T=set minute
	je FuncSetMinute
	cmp al,'N'		       ;N=set event number
	je FuncSetNumber
	cmp al,'P'		       ;P=change palette
	je FuncPalette1
	cmp al,'C'		       ;C=set mouse rate
	je FuncSetMouse
	cmp al,'W'		       ;W=save screen as Windows bitmap
	je SnapToBitmap

	IFE REPLAY
	cmp al,'L'		       ;L=toggle altitude alarm
	je FuncAlarmTog
	ENDIF

	IF PSEA
	cmp al,'K'
	je ChangeScheme
	ENDIF

	IF FAKENAV
	cmp al,'K'
	je NavSetup
	ENDIF

	IF DEMO
	cmp al,'X'		       ;X=rename disk
	je FuncDemo
	cmp al,'E'		       ;E=eject disk
	je FuncDemo
	cmp al,'U'		       ;U=erase last record
	je FuncDemo
	cmp al,'Z'		       ;Z=erase disk
	je FuncDemo
	cmp al,'F'		       ;F=start/stop towfish (coax)
	je FuncDemo
	cmp al,'I'		       ;I=range in
	je FuncDemo
	cmp al,'O'		       ;O=range out
	je FuncDemo
	ELSE
	cmp al,'X'		       ;X=rename disk
	je FuncRenameDisk
	cmp al,'E'		       ;E=eject disk
	je FuncEjectdisk
	cmp al,'U'		       ;U=erase last record
	je FuncEraseLast
	cmp al,'Z'		       ;Z=erase disk
	je FuncErasedisk
	IFE REPLAY
	cmp al,'F'		       ;F=start/stop towfish (coax)
	je FuncSwitchPower
	cmp al,'I'		       ;I=range in
	je FuncDecRange
	cmp al,'O'		       ;O=range out
	je FuncIncRange
	ENDIF
	ENDIF


	mov si,offset ErrorMsg3        ;invalid key
	call Rebuke
	JMP FunctionCancel


	IF PSEA
ChangeScheme:
	;this allows the user to customize the system colours
	mov si,offset AnBuff
	mov di,offset MonoScheme
	mov al,[si]
	cmp al,'M'
	je @f
	add di,9
	cmp al,'C'
	je @f
	jmp FunctionCancel
@@:
	inc si
	mov cl,9
ChangeS1:
	mov al,[si]
	cmp al,'U'
	je NoChgCol
	sub al,'0'
	cmp al,9
	jbe @f
	sub al,7
@@:
	cmp al,15
	ja NoChgCol
	mov [di],al
NoChgCol:
	inc di
	inc si
	dec cl
	jnz ChangeS1
	mov al,[di-7]			;get background colour
	shl al,4
	mov ah,al
	and dword ptr [di-6],0f0f0f0fh
	or [di-6],ax
	or [di-4],ax
	;save the scheme
	call SaveScheme
	;now redraw the status bar
	call SetScheme
	call PrintStatusBar
	jmp FunctionCancel
	ENDIF

FuncKeytest:
	mov AnnotationUsed,1
	mov di,offset KeytestMsg
	call petext
@@:
	call GetKey
	jnc @b
	call KeyboardBleep	       ;KEYBOARD BLEEP
	mov al,KeyCode
	cmp al,03ch		       ;stop?
	jne @b
	mov di,offset tspace
	call petext
	jmp KeyDone


	IFE FORCEEXPORT
SnapToBitmap:
	mov BitmapError,0
	;copy filename from anbuff
	cmp AnCur,0
	jne @f
	mov si,offset ErrorMsg30
	call Rebuke
	jmp FunctionCancel
@@:
	test SonarIsOn,1		;can't export in live mode
	je @f
	mov si,offset ErrorMsg15
	call Rebuke
	jmp FunctionCancel
@@:
	mov di,offset FileName
	mov si,offset anbuff
	mov cl,8
@@:
	lodsb
	cmp al,0ffh
	je @f
	mov [di],al
	inc di
	dec cl
	jnz @b
@@:
	mov eax,'PMB.'
	mov [di],eax
	mov byte ptr [di+4],0
	ELSE
SnapToBitmap:
	ENDIF

	mov SnapshotPending,040h
	jmp FunctionCancel

	IF FAKENAV

NavSetup:

	mov ax,cline
	sub ax,500
	and ax,BufferLimit
	mov DLine,ax
	jmp FunctionCancel

	mov bp,cline
	sub bp,50
	and bp,BufferLimit
	shl bp,3
	add bp,38h
	mov gs,bp
	mov si,offset NMEA1
	call FillNav
	mov bp,cline
	sub bp,240
	and bp,BufferLimit
	shl bp,3
	add bp,38h
	mov gs,bp
	mov si,offset NMEA2
	call FillNav
	mov bp,cline
	sub bp,430
	and bp,BufferLimit
	shl bp,3
	add bp,38h
	mov gs,bp
	mov si,offset NMEA3
	call FillNav
	mov bp,cline
	sub bp,620
	and bp,BufferLimit
	shl bp,3
	add bp,38h
	mov gs,bp
	mov si,offset NMEA4
	call FillNav
	jmp FunctionCancel

FillNav:
	or byte ptr gs:[0f8dh],08h
	mov di,03e0h
	mov cl,8
@@:
	mov eax,fs:[si]
	mov gs:[di],eax
	add si,4
	add di,4
	dec cl
	jnz @b
	ret
	ENDIF

	IF DEMO
FuncDemo:
	mov si,offset DemoMsg
	call Rebuke
	JMP FunctionCancel
	ENDIF

FuncToggleCache:
	xor CacheOff,1
	JMP FunctionCancel

FuncSwitchPower:
	;turn alarm off
	mov al,0
	out 61h,al
	mov dx,211h
	mov al,CoaxPower
	test al,8
	jne PowerIsOn
	;turn power on
	cmp StorageMode,1		;is play mode on?
	jne @f
	mov si,offset ErrorMsg8 	;in play mode
	call Rebuke
	JMP FunctionCancel
@@:
	test SonarIsOn,1
	je @f
	mov si,offset ErrorMsg37	;not coax
	call Rebuke
	JMP FunctionCancel
@@:
	;print 'waiting..'
	mov di,offset WaitingMsg
	call Petext
	;now wait for 20 seconds for a response
	mov SwitchTime,0
WaitTarget:
	test NewRangeFlag,1
	je @f
	;fish has started
	mov si,offset testMsg
	mov word ptr [si],'XC'
	mov byte ptr [si+2],0ffh
	call scrnad
	add bx,917
	mov al,LightStatText
	mov TextColour,al
	call bgtext
	jmp FunctionCancel
@@:
	cmp ClockTick,1
	jne @b
	mov ClockTick,0
	mov AL,00H
	out 070H,AL
	IN AL,071H		       ;get seconds from byte 0
	cmp al,Seconds
	je @b
	mov Seconds,al
	call StatusTime
	inc SwitchTime
	cmp SwitchTime,1
	jne @f
	;turn on power after 1 second
	mov al,8
	mov CoaxPower,al
	or al,2
	mov dx,211h
	out dx,al
@@:
	cmp SwitchTime,30		;give up at 10 seconds
	jne WaitTarget
	;no response from fish, turn power off
	mov CoaxPower,0
	mov dx,211h
	mov al,2
	out dx,al

	mov si,offset ErrorMsg40
	call Rebuke
	jmp FunctionCancel

PowerIsOn:
	mov al,2
	out dx,al
	mov CoaxPower,0
	jmp FunctionCancel


FuncRenameDisk:
	test StorageMode,3H		       ;can't rename in play or record mode
	je @F
	mov si,offset ErrorMsg15	;'wrong mode'
	call Rebuke
	JMP FunctionCancel
@@:
	call VerifyForRead		       ;make sure a disk is in
	jnc @f
	mov si,offset ErrorMsg7        ;'no disk'
	call Rebuke
	JMP FunctionCancel
@@:
	call VerifyForWrite
	je @f
	mov si,offset ErrorMsg2        ;'Write protected'
	call Rebuke
	jmp FunctionCancel
@@:
	call ldirs
	mov si,(offset dirsec+2016)
	cmp ancur,0		       ;if there is no text
	jne @f
	mov byte ptr [si],0	       ;mark no name
	jmp FuncRen1
@@:
	mov byte ptr [si],2		;mark volume name
	mov di,offset anbuff
	inc si
	mov eax,[di]
	mov [si],eax
	mov eax,[di+4]
	mov [si+4],eax
	mov ax,[di+8]
	mov [si+8],ax
FuncRen1:
	call wdirs
	jmp FunctionCancel

FuncSetMouse:
	;this sets the mouse sensitivity
	mov si,offset anbuff
	call GetDecimal
	jc @f
	dec dx
	cmp dx,4		       ;must be between 1 and 5
	ja @f
	mov al,4
	sub al,dl
	mov MouseRate,al
	call StoreCMOS5
	jmp FunctionCancel

@@:
	mov si,offset ErrorMsg12
	call Rebuke
	jmp FunctionCancel


FuncEraseLast:
	test StorageMode,3H		       ;can't erase in play or record mode
	je @F
	mov si,offset ErrorMsg15	;'wrong mode'
	call Rebuke
	JMP FunctionCancel
@@:
	mov al,FuncUCount
	inc al
	cmp al,3
	jae @f
	mov FuncUCount,al
	jmp KeyDone
@@:
	call VerifyForRead		       ;make sure a disk is in
	jnc @f
	mov si,offset ErrorMsg7        ;'no disk'
	call Rebuke
	JMP FunctionCancel
@@:
	call VerifyForWrite
	je @f
	mov si,offset ErrorMsg2        ;'Write protected'
	call Rebuke
	jmp FunctionCancel
@@:
	call ldirs
	mov si,offset dirsec
	cmp byte ptr [si],0
	jne @f
	mov si,offset ErrorMsg24       ;'No records'
	call Rebuke
	jmp FunctionCancel
@@:
	cmp byte ptr [si+32],0	       ;is this the last record
	je DelLastRec
	add si,32
	jmp @b

DelLastRec:
	mov cx,32
@@:
	mov byte ptr [si],0
	inc si
	loop @b
	call wdirs
	mov FuncUCount,0
	jmp FunctionCancel

FuncToggleEvent:	;toggle the event mark flag
	xor DisplayFlags,8
	jmp FunctionCancel

FuncErasedisk: ;erase disk
	test StorageMode,3H		       ;can't erase in play or record mode
	je @F
	mov si,offset ErrorMsg15	;'wrong mode'
	call Rebuke
	jmp FunctionCancel
@@:
	mov al,FuncZCount
	inc al
	cmp al,3
	jae @f
	mov FuncZCount,al
	jmp KeyDone
@@:
	call VerifyForRead		       ;make sure a disk is in
	jnc @f
	mov si,offset ErrorMsg7        ;'no disk'
	call Rebuke
	JMP FunctionCancel
@@:
	mov FuncZCount,0
	call ERASED
	JMP FunctionCancel
	mov si,offset ErrorMsg12
	call Rebuke
	jmp FunctionCancel

FuncDecRange:
FuncIncRange:
	mov ah,al			;save keystroke
	test CoaxPower,8
	jne @f
	mov si,offset ErrorMsg37
	call Rebuke
	jmp FunctionCancel
@@:
	;now find the next two possible ranges
	mov al,RangeNumber
	and al,0fh
	shl al,1
	movzx si,al
	cmp ah,'I'
	jne @f
	add si,18
@@:
	mov bx,RangeChangeTable[si]
	cmp bx,0a0ah			;0a0a=no valid search ranges
	jne FindTargetRanges
	mov si,offset ErrorMsg38
	call Rebuke
	jmp FunctionCancel

FindTargetRanges:
	push bx
	;print 'Changing..' message
	mov di,offset ChangingMsg
	call Petext
	pop bx
FindTarget1:
	;the power glitch must be synchronised with the telemetry phase
	mov NewRangeFlag,0
	mov edi,100000000
	mov RangeChange,0		;set on third byte of telemetry phase
@@:
	dec edi
	jz TargetTimeOut		;safety timeout (fish is stopped)
	test RangeChange,1
	je @b
	;switch coax power off
	mov CoaxPower,0
	mov al,2
	mov dx,211h
	out dx,al

	mov cx,CoaxPulse			;delay
@@:
	loop @b
	;switch power back on
	mov CoaxPower,8
	mov al,0ah
	mov dx,211h
	out dx,al

	mov esi,3000000
@@:
	push esi
	push bx
	call GetKey
	cmp al,3ch			;stop
	pop bx
	pop esi
	je FunctionCancel
	dec esi
	jz IncreasePulse		;safety timeout
	test NewRangeFlag,01		;wait for new range
	je @b				;success
	;new range found
	cmp RangeNumber,10		;bad line?
	jne @f
	mov NewRangeFlag,0
	jmp @b
@@:
	cmp RangeNumber,bh
	je @f
	cmp RangeNumber,bl
	jne FindTarget1
@@:
	;done
	jmp FunctionCancel

IncreasePulse:
	add CoaxPulse,2000
	cmp CoaxPulse,50000
	jae TargetTimeOut
	jmp FindTarget1

TargetTimeOut:
	mov CoaxPulse,3000
	mov si,offset ErrorMsg40
	call Rebuke
	jmp FunctionCancel



FuncSequence:	;get value from annotation buffer
	mov ch,al		       ;store 'S' or 'R'
	mov si,offset anbuff
	call GetDecimal
	jc @b
	cmp dx,10000		       ;must be <= 100
	ja @b

	mov SequenceCount,dx	       ;set up the sequence counter
	mov ah,01h
	cmp ch,'S'
	je @f
	mov ah,02h
@@:
	mov SequenceFlag,ah	       ;and signal 'Sequence'(or 'Repeat') on
	jmp FunctionCancel

FuncToggleAdjust:
	Xor ManualAltitude,01H		       ;toggle flag
	test ManualAltitude,1
	jne @f
	JMP FunctionCancel
@@:
	mov ScreenPan,4
	mov ScreenZoom,0
	mov ScreenGeometry,0
	mov MouseXCoord,160
	call StatusZoomPan		       ;and ZOOM MODE INDICATOR
	call StatusGeometry
	mov InitRedraw,1		       ;REDRAW NEEDED
	JMP FunctionCancel


FuncToggleAlt:	;toggle altidude
	Xor DisplayFlags,02H		       ;toggle flag
	JMP FunctionCancel

FuncToggleAnno:
	Xor DisplayFlags,01H		       ;toggle flag
	JMP FunctionCancel

FuncToggleTime:	;toggle time boxes
	Xor DisplayFlags,010H		       ;toggle flag
	JMP FunctionCancel

FuncToggleRange:
	Xor DisplayFlags,040h		       ;toggle flag
	JMP FunctionCancel

FuncPrintMenu:
	call RemoveArrow
	call SwapWindow		       ;clear old flags
	mov WindowFlag,010h	       ;signal printer menu active
	call ClearWindow	       ;clear window
	mov di,offset PrintMenuText	       ;pointer for printer menu text
	call PrintMenu		       ;print the menu
	call StatusPrntType
	call PrintArrow
	mov FreezeMode,1
	jmp KeyDone

FuncEjectdisk:
	test StorageMode,02H		       ;is it in record mode?
	Je @F			       ;if so, switch swap mode on
	mov SwapMode,1
	call RecordModeOff	       ;stop recording
@@:
	test StorageMode,1		       ;is play mode on?
	je @f			       ;if so, turn it of
	mov PAUSEF,00H		       ;reset pause flag
	mov StorageMode,00H
	call StatusMode		       ;UPDATE STATUS LINE
	mov FORWAD,00H		       ;reset cue control
	mov FWDINC,01H

	IF DOS			       ;interrupts
	mov AL,DOSINTMASK	       ;UART(5) MOUSE(4) keyboard(1)  nav(3)
	ELSE			       ;cascade
	mov al,REPINTMASK	       ;mouse (4) keyboard (1)
	ENDIF

	out 021H,AL
	mov SETTMF,00H
	call TestUnitReady	       ;test UNIT
	cmp DSTAT,00H
	je @f
	mov si,offset ErrorMsg7        ;'no disk'
	call Rebuke
	jmp KeyDone
@@:
	mov di,offset EjectingMsg
	call petext
	call EJECTD		       ;EJECT disk
	call PSCB		       ;BLANK CAPACITY
	;call SoundChime
	mov di,offset tspace
	call petext
	mov lastrn,0ffh 	       ;reset last record
	JMP FunctionCancel

FuncSetYear:
	call GETTWO
	cmp AL,0FFH
	je SETTME
	mov AH,AL
	mov AL,9
	out 070H,AL
	mov AL,AH
	out 071H,AL
	JMP @f

FuncSetMonth:
	call GETTWO
	cmp AL,0FFH
	je SETTME
	cmp AL,12H
	JA SETTME
	mov AH,AL
	mov AL,8
	out 070H,AL
	mov AL,AH
	out 071H,AL
	JMP @f

FuncSetDay:
	call GETTWO
	cmp AL,0FFH
	je SETTME
	cmp AL,31H
	JA SETTME
	mov AH,AL
	mov AL,7
	out 070H,AL
	mov AL,AH
	out 071H,AL
@@:
	;call StatusDate
	JMP FunctionCancel

FuncSetHour:
	call GETTWO
	cmp AL,0FFH
	je SETTME
	cmp AL,24H
	jae SETTME
	mov AH,AL
	mov AL,4
	out 070H,AL
	mov AL,AH
	out 071H,AL
	mov Hours,AL
	JMP FunctionCancel

FuncSetMinute:
	call GETTWO
	cmp AL,0FFH
	je SETTME
	cmp AL,60H
	jae SETTME
	mov AH,AL
	mov AL,2
	out 070H,AL
	mov AL,AH
	out 071H,AL
	mov Minutes,al
	mov AL,0		       ;reset seconds
	out 070H,AL
	out 071H,AL
	mov Seconds,al
	JMP FunctionCancel

FuncSetNumber:	;set the event number
	call getfour
	cmp dx,0ffffh		       ;error?
	je settme		       ;'invalid number'
	mov EventNumber,dx
	jmp FunctionCancel

FuncAlarmTog:	;toggles the altitude alarm
	xor AlarmControl,2
	jmp FunctionCancel

FuncPalette1:
	xor DisplayFlags,080h
	xor invpal,0ffH
	call setpal		       ;change VGA palette
	call SetScheme		       ;change screen colours
	call PrintStatusBar
	jmp FunctionCancel

SetScheme:
	mov si,offset MonoScheme
	mov di,offset WindowFrameLight
	test DisplayFlags,80h
	je @f
	add si,9
@@:
	mov cl,9
@@:
	mov al,[si]
	mov [di],al
	inc si
	inc di
	dec cl
	jnz @b
	ret


NavKey: ;sorts out nav menu options
	cmp al,'V'		       ;if the keypress is between V and Z
	jb @f			       ;a new baud rate is to be selected
	cmp al,'Z'
	jbe NavSelectBaud
@@:
	cmp AL,'D'		       ;D=hide nav data display
	je NavMenuHide
	cmp al,'F'
	je NavMenuShow
	cmp al,'E'
	je NavMenuPosOnly
	cmp al,'K'		       ;K=display speed in knots
	je NavMenuKnots
	cmp al,'M'		       ;M=display speed in m/s
	je NavMenuMetres
	cmp al,'S'
	je NavSetSpeed
	cmp al,'G'
	je NavSetHeading
	cmp al,'P'
	je NavSetPAngle
	cmp al,'N'
	je NavSetNAngle
	IF DOS
	cmp al,'R'
	je NavResetScope
	ENDIF
	mov si,offset ErrorMsg3        ;'invalid key'
	call Rebuke
	jmp prmcel



prmkey: ;sort out printer menu options
	cmp al,'0'		       ;if the keypress is between 0 and 9
	jb @f			       ;a new printer is to be selected
	cmp al,'9'
	jbe FuncNewPrinter
@@:
	cmp AL,'O'		       ;O=printer off
	je FuncPrintOff
	cmp AL,'A'		       ;A=print full width
	je FuncPrintFull
	cmp AL,'P'		       ;P=print left (port) hand side
	je FuncPrintLeft
	cmp AL,'S'		       ;S=print right hand side
	je FuncPrintRight
	cmp al,'G'		       ;G=toggle gamma correction
	je FuncGammaToggle
	cmp al,'T'		       ;T=printer test
	je FuncPrinttest
	cmp al,'D'
	je HPScreenDump
	cmp al,'L'
	je HPDumpLeft
	cmp al,'R'
	je HPDumpRight
	mov si,offset ErrorMsg3        ;'invalid key'
	call Rebuke
	jmp prmcel

FuncPrinttest:
	call InitializePrinter
	jc InitializeError
	mov PrinterMode,0	       ;full width
	mov Printtest,1
	call StatusPrntMode
	push es
	mov ax,30h		       ;point es to printer buffer
	mov es,ax
	xor edi,edi
	mov ecx,20000h
@@:
	mov ax,di
	shr ax,2		       ;fill buffer with test pattern
	mov es:[edi],al
	inc edi
	loop @b
	mov al,otail
	dec al
	and al,1fh
	mov ohead,al
	pop es
	mov testCount,40
@@:
	call [PrinterDriver]	       ;call the selected driver
	jc @f
	dec testCount
	jnz @b
@@:
	mov Printtest,0
	call StatusPrntMode
	jmp prmcel

FuncPrintOff:
	mov PrinterMode,00H		       ;reset mode to full width
	mov PFLAG,00H			       ;printer OFF
	call Flushp
	JMP prmcel

FuncPrintFull:
	cmp PrinterNumber,CONTDESK
	jb @f
	call InitializePrinter
	jc InitializeError
	mov PrinterMode,00H	       ;mode 00=full width
	mov PFLAG,1		       ;printer ON
	call flushp		       ;flush buffer
	JMP prmcel

FuncPrintLeft:
	cmp PrinterNumber,CONTDESK
	jb @f
	call InitializePrinter
	jc InitializeError
	mov PrinterMode,01H	       ;mode 01=left hand side, double size
	mov PFLAG,1		       ;printer ON
	call flushp		       ;flush buffer
	JMP prmcel

FuncPrintRight:
	cmp PrinterNumber,CONTDESK
	jb @f
	call InitializePrinter
	jc InitializeError
	mov PrinterMode,02H	       ;mode 02=right hand side, double size
	mov PFLAG,1		       ;printer ON
	call flushp		       ;flush buffer
	JMP prmcel

@@:
	mov si,offset ErrorMsg15
	jmp @f

InitializeError:
	mov si,offset ErrorMsg32
@@:
	call Rebuke
	jmp prmcel

FuncGammaToggle:
	xor GammaCorrection,1
	jmp prmcel

FuncNewPrinter:
	sub al,'0'		       ;turn '0'-'9' into 0-9
	call SelectPrinter
	call StoreCMOS5
	jmp prmcel

SelectPrinter:
	;this switches to a new printer driver
	;the printer number (0-9) in al
	movzx si,al
	shl si,2		       ;get al*4 in si
	mov bx,fs:PrintDrivers[si]     ;get address of printer driver
	cmp bx,0000h		       ;is driver valid?
	je @f			       ;bx=0 if driver not defined
	mov PrinterNumber,al
	mov PrinterDriver,bx	       ;update call indirection address
	mov ax,fs:PrintDrivers[si+2]   ;get compression factor for printer
	mov CompressionFactor,ax
	mov PrinterMode,0
	mov PFlag,0
	ret
@@:
	mov si,offset ErrorMsg20
	call Rebuke
	ret

NavResetScope:
	call DetectPulley
	jc NoPulleyError
	mov al,'R'
	call SendPulleyByte
	mov PulleyInstalled,1
	call StatusScope
	jmp prmcel


NoPulleyError:
	mov PulleyInstalled,0
	mov si,offset ErrorMsg36
	call Rebuke
	jmp prmcel


NavMenuHide:	;this hides all nav data
	and DisplayFlags,0ebh
	call StoreCMOS3
	jmp prmcel		       ;cancel menu

NavMenuShow:	;this displays all nav data
	or DisplayFlags,014h
	call StoreCMOS3
	jmp prmcel		       ;cancel menu

NavMenuPosOnly:	;this displays position data only
	mov al,DisplayFlags
	and al,0efh
	or al,04h
	mov DisplayFlags,al
	call StoreCMOS3
	jmp prmcel		       ;cancel menu

NavMenuKnots:	;this sets the speed display to knots
	or DisplayFlags,20h
	call StatusSpeed
	jmp prmcel

NavMenuMetres:	;this sets the speed display to metres/second
	and DisplayFlags,0dfh
	call StatusSpeed
	jmp prmcel

NavSelectBaud:	;this sets the nav data baud rate
	;newcode
	sub al,'U'
	call SetUartBaud
	call StoreCMOS5
	jmp prmcel

NavSetHeading:
	;set vessel course
	mov si,offset anbuff
	call GetDecimal
	jc @f
	cmp dx,359
	ja @f
	mov NavCourse,dx
	mov AnnotationUsed,1
	call StatusCourse
	jmp prmcel
@@:
	mov si,offset ErrorMsg23
	call Rebuke
	mov AnnotationUsed,1
	jmp prmcel

NavSetNAngle:
	mov ch,1
	jmp @f

NavSetPAngle:
	mov ch,0
@@:
	mov si,offset anbuff
	call GetDecimal
	jc AngleError
	cmp dx,45
	ja AngleError
	cmp ch,0
	je @f
	neg dl
@@:
	mov NavAngle,dl
	mov AnnotationUsed,1
	call StatusAngle
	jmp prmcel
AngleError:
	mov si,offset ErrorMsg18
	call Rebuke
	mov AnnotationUsed,1
	jmp prmcel


NavSetSpeed:	;THIS allows the user to enter the speed over seabed
	;first get a two digit number (not bcd)
	;from the user
	mov SI,offset ANBUFF
	call GetDecimal
	jc SpeedError
	shl dx,1
	mov ax,dx
	shl dx,2
	add dx,ax
	add dl,cl
	;if it is in knots, divide by two
	test DisplayFlags,20h
	je @f
	shr dx,1
@@:
	cmp dx,40			;max speed is 4.0 m/s
	ja SpeedError
	mov Speed,dl
	mov AnnotationUsed,1
	call StatusSpeed
	JMP prmcel


SpeedError:
	mov si,offset ErrorMsg21
	call Rebuke
	mov AnnotationUsed,1
	jmp prmcel


SETTME: ;SET DATE/TIME ERROR
	mov si,offset ErrorMsg12       ;'invalid number'
	call Rebuke
	JMP FunctionCancel

GETTWO: ;GET THE VALUE FROM THE ANBUFFER (2 digit BCD)
	mov SI,offset ANBUFF
	mov AL,[SI]
	sub al,30h
	cmp AL,9
	JA GTFAIL
	shl AL,4
	mov AH,[SI+1]
	sub ah,30h
	cmp AH,9
	JA GTFAIL
	add AL,AH
	RET
GTFAIL:
	mov AL,0FFH
	RET

GetFour: ;GET THE VALUE FROM THE ANBUFFER (4 digit BCD)
	mov SI,offset ANBUFF
	mov dx,00		       ;initial value
	mov cl,4		       ;four digits max
@@:
	mov AL,[SI]		       ;get digit
	cmp al,0ffh		       ;end of string?
	je @f
	sub al,30h		       ;ascii to number
	cmp AL,9		       ;valid?
	JA getfail		       ;fail if not
	shl dx,4		       ;add to total
	or dl,al
	inc si
	dec cl
	jnz @b
@@:
	RET

getfail:
	mov dx,0ffffH
	RET

DetectPulley:
	;mov dx,3edh
	;in al,dx
	;cmp al,0ffh
	;je @f				;no com3
	mov al,'I'
	call SendPulleyByte
	call GetPulleyByte
	jc @f
	cmp al,'P'
	jne @f
	clc
	ret
@@:
	stc
	ret

SendPulleyByte:
	mov dx,3e8h
	out dx,al
	mov dx,3edh
@@:
	in al,dx
	test al,40h
	je @b
	ret


GetPulleyByte:
	mov dx,3edh
	mov edi,20000h
@@:
	dec edi
	jz PulleyTimeOut
	in al,dx
	test al,1
	je @b
	mov dx,3e8h
	in al,dx
	clc
	ret

PulleyTimeOut:
	stc
	ret


ReadPulley:
	;send a (T)ransmit to the pulley
	mov al,'T'
	call SendPulleyByte
	;the pulley will respond with 6 bytes
	xor si,si
PulleyLoop:
	call GetPulleyByte
	jc PulleyEnd
	mov PulleyString[si],al
	cmp si,7
	je @f
	inc si
@@:
	cmp al,13
	jne PulleyLoop
	cmp si,6
	jne Pulley1

CalcPulleyValue:
	;now get the value
	xor ax,ax
	mov si,(offset PulleyString+1)
	mov dl,4
@@:
	shl ax,1
	mov bx,ax
	shl ax,2
	add ax,bx
	movzx bx,byte ptr [si]
	sub bl,'0'
	add ax,bx
	inc si
	dec dl
	jnz @b
	cmp PulleyString,'+'
	je @f
	neg ax
@@:
	clc
PulleyEnd:
	ret

Pulley1:
	mov ax,10000
	jmp @b

	IF PSEA
LoadScheme:
	;this loads the file 'CM800.COL' into 18 byte at 'MonoScheme'
	;if this file does not exist, carry is set on return
	call SwitchToRealMode
	mov ax,3d00h
	mov dx,offset ColourFile
	int 021h
	jc NoColours
	push ax 			;save handle
	mov bx,ax
	mov ah,03fh
	mov cx,18
	mov dx,offset MonoScheme
	int 021h			;load the file
	pop bx
	mov ah,03eh			;close it
	int 021h
	call SwitchToProtMode
	clc
	ret

NoColours:
	;the file 'CM800.COL' isn't there
	call SwitchToProtMode
	stc
	ret

SaveScheme:
	;this saves the current colour scheme to the file 'CM800.COL'
	call SwitchToRealMode
	mov ah,03ch			;create/truncate file
	xor cx,cx
	mov dx,offset ColourFile
	int 021h
	push ax 			;save handle
	mov bx,ax
	mov ah,40h
	mov cx,18
	mov dx,offset MonoScheme
	int 021h			;write colur scheme
	pop bx
	mov ah,03eh
	int 021h			;close file
	call SwitchToProtMode
	ENDIF

flushp: ;flush the printer buffer
	mov ax,cline		       ;reset source line
	mov oline,ax
	mov al,00h
	mov ohead,al		       ;reset cyclic buffer pointers
	mov otail,al
	and AlarmFlag,0efh	       ;kill lag alarm
	ret

ClearWindow:
	;clears the lower window of the screen for help, directory etc
	call RemoveArrow		       ;erase arrow

	mov AX,0FF08H
	call SETGCR		       ;BIT MASK=FFH

	call SCRNAD		       ;GET TOP OF SCREEN
	add BX,9040		       ;get top of window
	mov si,bx
	mov CX,29860		       ;number of bytes in window
	mov AL,WindowBackground	       ;colour to fill with
@@:
	mov ES:[BX],AL		       ;write colour
	inc BX			       ;increment pointer
	LOOP @B 		       ;loop round
	;first print the light colour top
	;and dark colour bottom bars
	mov bx,si		       ;si is pointer for light top
	lea di,[bx+29200]	       ;di for dark bottom
	mov dl,WindowFrameLight	       ;dl=light, dh=dark
	mov dh,WindowFrameDark
	mov ch,80		       ;new length counter
@@:
	mov ah,es:[si]		       ;dummy read
	mov es:[si],dl		       ;write light colour
	mov ah,es:[si+50h]	       ;dummy read
	mov es:[si+50h],dl	       ;write light colour
	inc si			       ;inrement pointer
	mov ah,es:[di]		       ;dummy read
	mov es:[di],dh		       ;write dark colour
	mov ah,es:[di+50h]	       ;dummy read
	mov es:[di+50h],dh	       ;write dark colour
	inc di			       ;increment pointer
	dec ch
	jnz @b
	;now print the light left hand side
	mov si,bx
	add si,160
	mov cx,364
	mov dx,03cfh		       ;point dx back to vga data
	mov al,0c0h
	out dx,al		       ;set bit mask to 11000000
	mov ah,WindowFrameLight	       ;light colour
@@:
	mov al,es:[si]		       ;dummy read
	mov es:[si],ah		       ;write colour
	add si,50h		       ;next screen line down
	loop @b
	mov al,080h		       ;set bit mask to 10000000
	out dx,al
	mov al,es:[si]		       ;and print one dot
	mov es:[si],ah
	;now print the dark right hand side
	lea si,[di-81]
	mov cx,364
	mov al,03h
	out dx,al		       ;set bit mask to 00000011
	mov ah,WindowFrameDark	       ;dark colour
@@:
	mov al,es:[si]		       ;dummy read
	mov es:[si],ah		       ;write colour
	sub si,50h		       ;next screen line up
	loop @b
	mov al,01h		       ;set bit mask to 00000001
	out dx,al
	mov al,es:[si]		       ;and print one dot
	mov es:[si],ah
	mov ch,0
	add bx,cx
	ret			       ;done


StatusGeometry:
	;PRINT GEOMETRY STATUS
	mov di,offset PSGMMSG
	mov AL,ScreenGeometry
	shl AL,3
	mov AH,00H
	add di,AX
	mov al,LightStatText
	mov TextColour,al
	call scrnad
	add bx,2902
	call CopyMessage
	call bgtext
	ret


psinit:
	;now print a row of raised boxes across the top of the screen


	call scrnad
	mov cl,13
	call psbox		       ;nav parameters

	mov cl,8
	call psbox

	mov cl,10
	call psbox		       ;display controls

	mov cl,11		       ;towfish data
	call psbox

	mov cl,15		       ;record name, disk capacity etc.
	call psbox

	mov cl,14
	call psbox		       ;annotation, measurement and errors

	;mov cl,9
	;call psbox		       ;printer status

	mov cl,9
	call psbox		       ;time and print mode
	;now print feature titles eg Fish
	mov al,DarkStatText
	mov TextColour,al
	;now print the status bar parameter title eg 'Speed'
	mov si,offset StatusMsgTable
@@:
	call scrnad
	add bx,fs:[si]			       ;get screen address
	mov di,fs:[si+2]		       ;and message offset
	add si,4
	cmp di,0ffffh			       ;end of table marker
	je @f
	push si
	call CopyMessage
	call smtext
	pop si
	jmp @b
@@:
	ret


CopyMessage: ;copies a message from FS:[DI] to DS:[testmsg] until a 0ffh is found
	;leaves SI at offset testmsg ready for smtext or bgtext
	mov si,offset testmsg
@@:
	mov al,fs:[di]
	mov [si],al
	inc si
	inc di
	cmp al,0ffh
	jne @b
	mov si,offset testmsg
	ret

psblank:;prints a grey	block behind the status line
	call scrnad		       ;top of screen in BX
	mov cx,4160		       ;4160 bytes to fill
	mov dx,03CEH
	mov al,8		       ;POINT VGA INDEX TO BIT MASK
	out dx,al
	inc dx			       ;point to vga data
	mov al,0ffh		       ;bit mask is 11111111
	out dx,al		       ;set it
	mov ah,WindowBackground	       ;colour
@@:
	mov es:[bx],ah		       ;write colour
	inc bx			       ;inrement pointer
	loop @b 		       ;loop
	ret			       ;finish

psgrsc: ;prints a palette scale bar
	call scrnad
	add bx,2429		       ;screen address of bar
	mov si,bx
	mov bx,offset ScreenGamma
	test DisplayFlags,80h
	je @f
	add bx,16
@@:
	mov dx,3ceh
	mov al,8		       ;set vga index to bit mask
	out dx,al
	inc dx
	mov al,0ffh
	out dx,al
	mov ah,0
@@:
	mov al,ah
	xor al,invpal
	and al,0fh
	xlatb fs:ScreenGamma
	mov es:[si],al
	add si,050h
	inc ah
	cmp ah,16
	jne @b
	ret


psbox:	;prints a windows button style box on the status line
	;length is in CL
	;address is in bx which is advanced by CL
	mov dx,03CEH
	mov al,8		       ;set vga index to bit mask
	out dx,al
	inc dx			       ;point to vga data
	mov al,0ffh
	out dx,al
	;first print the light colour (5) top
	;and dark colour (9) bottom bars
	mov si,bx		       ;si is pointer for light top
	lea di,[bx+4000]	       ;di for dark bottom
	mov dl,WindowFrameLight	       ;dl=light, dh=dark
	mov dh,WindowFrameDark
	mov ch,cl		       ;new length counter
@@:
	mov ah,es:[si]		       ;dummy read
	mov es:[si],dl		       ;write light colour
	mov ah,es:[si+50h]	       ;dummy read
	mov es:[si+50h],dl	       ;write light colour
	inc si			       ;inrement pointer
	mov ah,es:[di]		       ;dummy read
	mov es:[di],dh		       ;write dark colour
	mov ah,es:[di+50h]	       ;dummy read
	mov es:[di+50h],dh	       ;write dark colour
	inc di			       ;increment pointer
	dec ch
	jnz @b
	;now print the light left hand side
	mov si,bx
	add si,160
	mov ch,49
	mov dx,03cfh		       ;point dx back to vga data
	mov al,0c0h
	out dx,al		       ;set bit mask to 11000000
	mov ah,WindowFrameLight	       ;light colour
@@:
	mov al,es:[si]		       ;dummy read
	mov es:[si],ah		       ;write colour
	add si,50h		       ;next screen line down
	dec ch			       ;loop round 49 times
	jnz @b
	mov al,080h		       ;set bit mask to 10000000
	out dx,al
	mov al,es:[si]		       ;and print one dot
	mov es:[si],ah
	;now print the dark right hand side
	lea si,[di-81]
	mov ch,49
	mov al,03h
	out dx,al		       ;set bit mask to 00000011
	mov ah,WindowFrameDark	       ;dark colour
@@:
	mov al,es:[si]		       ;dummy read
	mov es:[si],ah		       ;write colour
	sub si,50h		       ;next screen line up
	dec ch			       ;loop round 49 times
	jnz @b
	mov al,01h		       ;set bit mask to 00000001
	out dx,al
	mov al,es:[si]		       ;and print one dot
	mov es:[si],ah
	mov ch,0
	add bx,cx
	ret			       ;done

WriteFilename:
	;copy filename into testmsg
	movzx si,CURPLY
	shl si,5
	add SI,(offset DIRSEC+1)
	mov di,(offset testmsg+3)
	mov cl,10
@@:
	mov al,[si]
	mov [di],al
	inc si
	inc di
	dec cl
	jnz @b
	mov byte ptr [di],0ffh
	mov al,CurPly
	call StatusRecord
	ret

StatusRecord:
	;prints the record name and number of the current record
	;the number is supplied in al
	mov si,offset testmsg		;write string into testmsg
	mov di,si
	inc al				;record number
	aam				;split into decimal digits
	add ax,3030h			;convert to ascii
	cmp ah,'0'			;leading zero?
	jne @f
	mov ah,al
	mov al,'|'			;if so, replace with blank
@@:
	xchg al,ah
	mov [si],ax			;place in string
	mov byte ptr [si+2],' '
	;now convert any 0ffh in the name to a ' ' character
	mov cl,13
	mov al,0ffh
StatRec1:
	cmp byte ptr [di],al
	jne @f
	mov al,' '
	mov byte ptr [di],al
@@:
	inc di
	dec cl
	jnz StatRec1
	mov byte ptr [di],0ffh
@@:
	mov al,LightStatText
	mov TextColour,al
	call ScrnAd
	add bx,923
	mov ch,105
	call ForceLength		       ;print big text
	ret

ClearFilename:
	mov si,offset testMsg
	mov byte ptr [si],0ffh
	jmp @b


StatusMode:
	;PRINT SONAR MODE (Live,Record,Play,Cue,Edit,Off,Pause,Swap)
	cmp SonarIsOn,01H	       ;is the sonar on?
	je @f			       ;if so, jump
	call blbat		       ;clear battery voltage
	cmp StorageMode,1		       ;is play mode on?
	je @f			       ;if so, jump
	call blhgt		       ;clear altitude
@@:				       ;either way comes here
	mov di,offset StatusModeMSG
	cmp EditOnFlag,01H
	jne @F
	add di,28		       ;EDIT
	JMP PSSON1
@@:
	cmp SwapMode,01H
	jne @F
	add di,49		       ;Swap
	JMP PSSON1
@@:
	cmp StorageMode,01H
	jne PSSON2
	add di,14		       ;PLAY or CUE
	cmp FORWAD,01H
	jne @F			       ;PLAY
	add di,7		       ;CUE
@@:
	cmp pausef,1
	jne @f
	mov di,(offset StatusModemsg+42)	;pause
@@:
	JMP PSSON1
PSSON2:
	cmp StorageMode,02H
	jne PSSON3

	add di,7		       ;REC

PSSON1:
	mov al,LightStatText
	mov TextColour,al
FlashLive:
	call CopyMessage
	call scrnad
	add bx,2923
	call bgtext
	RET
PSSON3:
	test SonarIsOn,01H
	jne @f
	add di,35
	JMP PSSON1

@@:
	mov al,Seconds			;live
	and al,1
	neg al
	and al,07h
	or al,70h
	mov TextColour,al
	mov di,offset StatusModemsg
	jmp FlashLive

pssp:
	ret

StatusSpeed:
	;this prints the speed over ground
	mov si,offset testmsg
	mov al,speed		       ;get speed in 0.1 m/s
	test DisplayFlags,20h	       ;if speed display is in knots,
	je @f
	shl al,1		       ;double it 2knots=1m/s
@@:
	;check limits
	cmp al,99
	jbe @f
	ret
@@:
	aam
	add ax,3030h
	mov [si],ah
	mov byte ptr [si+1],'.'
	mov [si+2],al
	mov eax,0ff3c746bh	       ;'kt',0ffh backwards
	test DisplayFlags,20h
	jne @f
	mov eax,0ff736dh	       ;'ms',0ffh backwards
@@:
	mov [si+3],eax
	mov al,LightStatText
	mov TextColour,al
	call scrnad
	add bx,881		       ;get address in bx
	call bgtext		       ;print big text
	ret

StatusSounding:
	;prints the depth sounding in metres   881
	mov si,offset testmsg
	mov ax,Sounding
	cmp ax,9999
	jbe @f
	ret
@@:
	cmp ax,0
	je NoSounding
	xor dx,dx
	mov bx,10
	div bx
	add dl,'0'
	mov ch,dl			;tenths of metres in ch
	call PrintMetres
	;mov cl,'.'
	;mov [si+1],cx
	;mov word ptr [si+1],0ff6dh
@@:
	call scrnad
	add bx,2894		       ;get address in bx
	mov ch,48
	mov si,offset testmsg
	call ForceLength	       ;print big text
	ret
NoSounding:
	mov al,LightStatText
	mov TextColour,al
	mov dword ptr [si],0ff612f6eh	;'n/a'
	jmp @b


StatusScope:
	;prints the cable scope in metres
	mov si,offset testmsg
	test PulleyInstalled,1
	je NoScope
	mov ax,CableScope
	test ax,8000h			;negative value?
	je @f
	neg ax
	mov byte ptr [si],'-'
	inc si
@@:
	call PrintMetres
@@:
	call scrnad
	add bx,894		       ;get address in bx
	mov ch,48
	mov si,offset testmsg
	call ForceLength	       ;print big text
	ret

NoScope:
	mov al,LightStatText
	mov TextColour,al
	mov dword ptr [si],0ff612f6eh	;'n/a'
	jmp @b

StatusLayback:
	;prints the layback in metres
	mov si,offset testmsg
	mov ax,NavLayBack
	cmp ax,9999
	jbe @f
	ret
@@:
	call PrintMetres
	call scrnad
	add bx,887		       ;get address in bx
	mov ch,41
	mov si,offset testmsg
	call ForceLength	       ;print big text
	ret

PrintDecimal:
	xor dx,dx		       ;initial value dx:ax
	mov cl,dl		       ;digit printed flag
	mov bx,1000
	div bx			       ;get thousands of metres in ax
	cmp al,0
	je @f
	add al,'0'		       ;if it is non zero
	mov [si],al		       ;print it
	inc si
	mov cl,1		       ;signal digit printed
@@:
	mov bx,100
	mov ax,dx
	xor dx,dx
	div bx			       ;get hundreds of metres
	add cl,al
	cmp cl,0
	je @f
	add al,'0'		       ;if it is non zero
	mov [si],al		       ;print it
	inc si
	mov cl,1		       ;signal digit printed
@@:
	mov al,dl		       ;get remaining metres in dl
	aam			       ;split into decimal
	add ax,'00'
	cmp cl,0
	jne @f
	cmp ah,'0'
	je PDecimal1
@@:
	mov [si],ah
	inc si
PDecimal1:
	mov [si],al
	inc si
	ret

PrintMetres:
	call PrintDecimal
	mov word ptr [si],0ff6dh	;m,0ff
	mov al,LightStatText
	mov TextColour,al
	ret


StatusAngle:
	mov si,offset testmsg
	mov al,NavAngle
	mov ah,'+'
	cmp al,0
	jge @f
	neg al
	mov ah,'-'
@@:
	cmp al,45
	jbe @f
	ret
@@:
	mov [si],ah
	aam
	xchg al,ah
	add ax,3030h
	mov [si+1],ax
	mov word ptr [si+3],' *'
	mov byte ptr [si+5],0ffh
	mov al,LightStatText
	mov TextColour,al
	call scrnad
	add bx,2887		       ;get address in bx
	call bgtext		       ;print big text
	ret			       ;finish

StatusCourse:
	mov si,offset testmsg
	mov ax,NavCourse
	cmp ax,359
	jbe @f
	ret
@@:
	mov bl,02fh
@@:
	inc bl
	sub ax,100
	jnc @b
	add ax,100
	mov [si],bl
	aam
	add ax,3030h
	mov [si+1],ah		       ;most sig. fig.
	mov [si+2],al		       ;least sig. fig.
	mov byte ptr [si+3],'*'
	mov byte ptr [si+4],0ffh       ;terminator
	call scrnad
	add bx,2881		       ;position in screen
	mov al,LightStatText
	mov TextColour,al
	call bgtext		       ;print big text
	ret

PSCB:
	;PRINTS BLANK OVER CAPACITY
	mov si,offset testmsg
	mov word ptr [si],2020h        ;'  '
	mov word ptr [si+2],2020h	;'  '
	mov byte ptr [si+4],0ffh
	jmp pscap1


blbat:	;blanks out the battery voltage
	mov si,offset testmsg			 ;battery voltage
	mov word ptr [si],2020h        ;'  '
	mov word ptr [si+2],2020h	;'  '
	jmp psbat1

StatusSpace:
	;PRINT STORE CAPACITY REMAINING
	mov AL,STCAP		       ;CAPACITY IN AL
	aam
	add ax,3030h
	mov si,offset testmsg
	xchg al,ah
	mov word ptr [si],ax
	mov byte ptr [si+2],'%'
	mov byte ptr [si+3],0ffh
pscap1:
	mov al,LightStatText
	mov TextColour,al
	call scrnad
	add bx,2929
	call bgtext
	ret

StatusPrntMode:
	mov di,offset PrntModeMsg
	test Printtest,1
	je NottestMode
	mov di,offset testModeMsg
	jmp @f

NottestMode:
	test PFlag,1		       ;is the printer on?
	je @f
	mov al,PrinterMode
	inc al
	mov ah,al
	shl al,2
	add al,ah
	shl al,1
	add al,ah
	mov ah,0
	add di,ax
@@:
	call CopyMessage
	mov al,LightStatText
	mov TextColour,al
	call scrnad
	add bx,2952
	call bgtext
	ret

StatusPrntType:
	mov di,offset PrntTypeMsg
	mov al,PrinterNumber
	mov ah,al
	shl al,2
	add al,ah
	shl al,1
	mov ah,0
	add di,ax
	call CopyMessage
	mov al,LightStatText
	mov TextColour,al
	call scrnad
	add bx,12218
	mov ch,62
	call ForceLength
	ret

StatusDate:
	mov al,LightStatText
	mov TextColour,al
	mov di,offset testmsg
	call WriteDate
	mov si,offset testmsg
	call scrnad
	add bx,9989
	call bgtext
	ret

StatusTime:	;PRINTS THE TIME
	mov al,LightStatText
	mov TextColour,al
	mov si,offset testmsg
	mov AL,HOURS
	mov ah,al
	shr AL,4
	add al,30h
	mov [si],al
	and ah,0FH
	add ah,30h
	mov [si+1],ah
	mov byte ptr [si+2],':'
	mov AL,MINUTES
	mov ah,al
	shr AL,4
	add al,30h
	mov [si+3],al
	and ah,0FH
	add ah,30h
	mov [si+4],ah
	mov byte ptr [si+5],'.'
	mov al,Seconds
	mov ah,al
	shr AL,4
	add al,30h
	mov [si+6],al
	and ah,0FH
	add ah,30h
	mov [si+7],ah
	mov byte ptr [si+8],0ffh
	call scrnad
	add bx,952
	call bgtext
	RET


StatusBattery:	;PRINTS BATTERY VOLTAGE
	test CoaxPower,8
	je @f
	ret
@@:
	mov al,BatteryVoltage
	IF NOOFBITS EQ 6
	xor al,0ffH		       ;78bit
	ELSE
	xor al,07fh
	ENDIF
	mov AH,0		       ;31 mV per unit in ax
	mov BX,AX		       ;1
	shl ax,5		       ;32
	sub ax,bx		       ;31
	add ax,4000		       ;+4 volts offset
	mov si,offset testmsg

	mov BL,100
	div bl
	aam
	add ax,3030h
	mov [si],ah
	mov byte ptr [si+1],'.'
	mov [si+2],al
	mov byte ptr [si+3],'v'
psbat1:
	mov byte ptr [si+4],0ffh
	call scrnad
	add bx,917
	mov al,LightStatText
	mov TextColour,al
	call bgtext
	RET



StatusZoomPan:			       ;PRINT PAN/ZOOM WINDOW
	;*test
	IF HIPOWER
	mov ax,0ffh
	mov cl,ScreenPan
	shl ax,cl
	mov al,ah
	mov dx,210h
	out dx,al
	ENDIF
	;*test
	call scrnad
	add bx,1142
	lea si,[bx+8]
	mov dx,03ceh		       ;set vga index to bit mask
	mov al,8
	out dx,al
	inc dx
	mov AL,ScreenZoom
	test AL,1
	jne PSZW1
	mov ch,8
	mov al,0ffh
@@:
	call pzwblk
	dec ch
	jnz @b
	RET			       ;finished

PSZW1:				       ;OTHERWISE PRINT LEADING
			       ;int (pan/2) clear blocks
	mov ch,ScreenPan
	shr ch,1
	jz PSZW4
	mov al,00h
@@:
	call pzwblk
	dec CH
	jnz @b

PSZW4:
	mov ch,ScreenPan	       ;IF PAN IS ODD, print half black block
	shr ch,1		       ;OTHERWISE PRINT black
	mov al,0fh
	jc @f
	mov al,0ffh
@@:
	call pzwblk

	mov AL,ScreenZoom	       ;if zoom is x4 print 1 black block
	mov CH,01H		       ;if zoom is x2 print 3 black blocks
	test AL,04H
	jne @f
	mov CH,03H
@@:
	mov al,0ffh
@@:
	call pzwblk
	dec CH
	jnz @b

	mov AL,ScreenPan	       ;if pan is odd print half
	shr AL,1		       ;otherwise print clear
	JNC @f
	mov al,0f0h
	call pzwblk
@@:				       ;run to end with clear blocks
	mov al,00h
	cmp bx,si
	je @f
	call pzwblk
	JMP @b
@@:
	RET

pzwblk: ;prints a pan\zoom window block with colour mask al
	;assumes vga index is at bit mask
	;screen address in bx
	out dx,al
	mov cl,9
@@:
	mov ah,es:[bx]
	mov byte ptr es:[bx],0	      ;dark
	add bx,50h
	dec cl
	jnz @b
	sub bx,720
	xor al,0ffh		       ;invert bit mask
	out dx,al
	mov cl,9
@@:
	mov ah,es:[bx]
	mov byte ptr es:[bx],7	       ;light
	add bx,50h
	dec cl
	jnz @b
	sub bx,719		       ;advance screen address 1
	xor al,0ffh		       ;restore bit mask
	ret

SquareRoot:
	;this returns the square root of eax in ax
	;using the iteration to find root C
	;A(estimate)=C
	;new A=(A+A/C)/2
	;eax=C
	;first see if C is zero
	;if so give the result as zero
	;to avoid crashing the division with /0 error
	cmp eax,0		       ;is C zero
	je RootZero
	mov ebx,eax		       ;ebx holds estimate A
	mov ecx,eax		       ;ecx holds argument C
@@:
	;first find C/A  (ecx/ebx)
	mov esi,ebx
	mov eax,ecx
	cdq			       ;set edx=0 for 32 bit division
	div ebx 		       ;result in eax
	add ebx,eax		       ;A=A+(C/A)
	shr ebx,1		       ;half it
	cmp ebx,esi		       ;changed?
	jne @b
	mov ax,bx		       ;result in ax
RootZero:
	ret

CalcSquares: ;THIS GENERATES THE SQUARE TABLE USED IN SRC and Map modes
	mov DI,offset SquaresTable     ;START OF TABLE
	mov CX,2048		       ;NUMBER OF SQUARES
	xor bx,bx		       ;FIRST NUMBER
@@:
	mov AX,BX
	MUL BX			       ;DX:AX=AX SQUARED
	mov [DI],AX
	mov [DI+2],DX
	add di,4
	inc BX
	LOOP @b
	RET

CalcLogarithms:
	mov bx,0
@@:
	;calculate LogMultiple*[log2((bl/LogFactor)+2)-1]
	mov ax,bx
	neg al
	mov LogValue,ax
	fld1				;load 1.0
	fild LogValue			;load bl
	fdiv cs:LogFactor		;(bl/LogFactor)
	fadd cs:RealTwo 		;(bl/LogFactor)+2
	fyl2x				;log2((bl/LogFactor)+2)
	fld1				;load 1.0
	fsub				;[log2((bl/LogFactor)+2)-1]
	fmul cs:LogMultiple		;
	fistp LogValue
	mov ax,LogValue
	neg al
	mov LogsTable[bx],al
	inc bl
	jnz @b
	ret

LogFactor   real4   16.0
RealTwo real4 2.0
LogMultiple real4 80.57


KeyboardBleep:
	in al,61h
	xor al,03h
	out 061H,AL
	mov AL,10
KEBDEL:
	mov CX,4000H
@@:
	LOOP @B
	dec AL
	jnz KEBDEL
	in al,61h
	xor al,03h
	out 061H,AL
	RET

SoundChime:
	mov bx,0500h
	in al,61h
	or al,03h
	out 061H,AL
Chime2:
	mov AL,0B6H		       ;set up timer
	out 43H,al
	mov AL,bl
	out 42H,AL
	mov AL,bh
	out 42H,AL
	mov AL,10
Chime1:
	mov cx,0ffffH
@@:
	LOOP @B
	dec AL
	jnz Chime1
	sub bx,80h
	cmp bh,2
	jne Chime2
	jmp @f

Rebuke: ;sounds a Rebuke bleep
	mov al,KeyBufHead
	mov KeyBufTail,al

	inc FaultCount
	mov AL,0B6H		       ;set up timer for low sound
	out 43H,AL
	mov AL,00H
	out 42H,AL
	mov AL,10
	out 42H,AL
	mov AL,3
	out 061H,AL		       ;turn on low sound

	call PrintErrorMsg

@@:
	mov AL,0B6H		       ;set up timer for high sound
	out 43H,AL
	mov AL,00H
	out 42H,AL
	mov AL,5
	out 42H,AL
	mov AL,0		       ;turn speaker off
	out 061H,AL
	RET

CompressChar:
	;checks if the character in al is '0'-'9', ',' or '.'
	;'$', 'G', 'P', or 'L'
	;if so, returns with carry set, the lower 4 bits
	;of al are set as below, otherwise al is unchanged
	;ascii	    out
	;0	    00
	;1	    01
	;:	    ::
	;9	    09
	;,	    0a
	;.	    0b
	;$	    0c
	;G	    0d
	;P	    0e
	;L	    0f
	cmp al,'0'
	jb @f
	cmp al,'9'
	ja @f
	sub al,'0'			;convert to value
	stc
	ret
@@:
	cmp al,','
	jne @f
	mov al,0ah
	stc
	ret
@@:
	cmp al,'.'
	jne @f
	mov al,0bh
	stc
	ret
@@:
	cmp al,'$'
	jne @f
	mov al,0ch
	stc
	ret
@@:
	cmp al,'G'
	jne @f
	mov al,0dh
	stc
	ret
@@:
	cmp al,'P'
	jne @f
	mov al,0eh
	stc
	ret
@@:
	cmp al,'L'
	jne @f
	mov al,0fh
	stc
	ret
@@:
	clc				;return al unchanged
	ret

StoreNibble:
	;stores the nibble in the lower 4 bits of al
	;CompNavString[di/2]

	push di
	shr di,1
	jc @f				;high or low nibble
	;low nibble
	mov CompNavString[di],al
	jmp StoreNibb1
@@:
	;high nibble
	shl al,4
	or CompNavString[di],al
StoreNibb1:
	pop di
	inc di
	cmp di,63			;last nibble?
	cmc				;carry set if so
	ret

GetNibble:
	;gets a nibble from gs:[(si/2)+0fc0h]
	;if si is even, the nibble is from the
	;lower 4 bits of gs:[(si/2)+0fc0h]
	;increments si
	push si
	shr si,1
	jc @f				;high or low nibble
	;low nibble
	mov al,gs:[si+0fc0h]
	and al,0fh
	jmp GetNibb1
@@:
	;high nibble
	mov al,gs:[si+0fc0h]
	shr al,4
GetNibb1:
	pop si
	inc si
	cmp si,63			;last nibble?
	cmc				;carry set if so
	ret

UnCompress:
	;this uncompresses the nav data string from gs:[0fc0h]
	;in to a buffer at [di]
	xor si,si		       ;source pointer
	cmp byte ptr gs:[si+0fc0h],'$'	;uncompressed data?
	je NonComp
	mov bx,offset TransDigit       ;nibble translation table
UnCompMain:
	call GetNibble
	jc UnCompDone
	cmp al,0fh		       ;end of string?
	je UnCompDone
	cmp al,0		       ;ascii string?
	je UnCompAscii
	;expand digit string
	mov dl,al		       ;digit count
@@:
	call GetNibble		       ;get digit
	jc UnCompDone
	xlatb fs:[TransDigit]	       ;translate digit
	mov [di],al
	inc di
	dec dl
	jnz @b
	jmp UnCompMain		       ;done

UnCompAscii:
	;expand ascii string
	call GetNibble
	jc UnCompDone
	mov ah,al
	call GetNibble
	jc UnCompDone
	shl al,4
	or al,ah
	mov ah,al
	and al,07fh			;remove bit 7
	mov [di],al
	inc di
	test ah,80h			;last character?
	je UnCompAscii
	jmp UnCompMain			;done

UnCompDone:
	mov byte ptr [di],0ffh
	ret

NonComp:
	;copy the 32 bytes from gs:[0fc0h] to [di]
	mov si,0fc0h
	mov dl,8
@@:
	mov eax,gs:[si]
	mov [di],eax
	add si,4
	add di,4
	dec dl
	jnz @b
	ret

ValidNavString:
	;this scans the string at [di] and sets the carry if
	;if contains no valid nav header eg 'GLL','GGA','KR.'
	;or is not a valid UTM string
	;on exit al holds the fix type
	;0 GLL
	;1 GGA
	;2 UTM
	;3 KART
	push di
	call ValidUTM
	pop di
	jc @f
	;string is a valid UTM string
	mov al,2
	ret
@@:
	mov eax,[di]
	cmp eax,' ,RK'
	jne @f
	;string is a valid KART string
	mov al,3
	ret
@@:
	mov eax,[di+3]
	cmp eax,',LLG'
	jne @f
	mov al,0
	ret
@@:
	mov eax,[di+3]
	cmp eax,',AGG'
	jne @f
	mov al,1
	ret
@@:
	stc
	ret



ValidUTM:
	;this scans the string at [di] and sets the carry if
	;it contains no valid X and Y fix
	cmp byte ptr [di],'$'
	jne @f
	stc
	ret
@@:
	push bx
	push si
	mov bp,di
	call GetXFix
	jc @f
	mov di,bp
	call GetYFix
@@:
	pop si
	pop bx
	ret


GetYFix:
	;this returns the Y value in EDX
	mov bx,'YN'
	jmp @f
GetXFix:
	;this returns the X value in EDX
	mov bx,'XE'
@@:
	mov EastNorth,0
	;first find X, Y, E or N
	mov al,[di]
	inc di
	cmp al,0ffh			;end of string?
	je NoXYFix
	cmp al,bh
	je @f
	cmp al,bl
	jne @b
	mov EastNorth,1
@@:
	;check for commas
	cmp byte ptr [di+1],','
	je NoXYFix
	;now skip any spaces
	cmp byte ptr [di],' '
	jne @f
	inc di
	jmp @b
@@:
	mov bl,[di]			;any sign?
	mov bh,1
	cmp bl,'-'
	je @f
	mov bh,0
	cmp bl,'+'
	je @f
	dec di
@@:
	inc di
	;number is negative if bh=1
	xor edx,edx		       ;total
GetEDXLoop:
	xor eax,eax
	mov al,[di]		       ;get character
	cmp al,0ffh		       ;end of string
	je @f			       ;finish if so
	cmp al,' '		       ;end of string
	je @f			       ;finish if so
	cmp al,'.'		       ;end of string
	je @f			       ;finish if so
	cmp al,','		       ;end of string
	je @f			       ;finish if so
	shl edx,1
	jc NoXYFix		       ;overflow
	mov esi,edx
	shl edx,2
	jc NoXYFix		       ;overflow
	add edx,esi		       ;multiply dx by 10
	jc NoXYFix		       ;overflow
	cmp al,'0'		       ;check digit is in range
	jb NoXYFix
	cmp al,'9'
	ja NoXYFix
	sub al,'0'
	add edx,eax		       ;add into total
	jc NoXYFix		       ;overflow
	inc di
	jmp GetEDXLoop
@@:
	;done
	cmp bh,1
	jne @f
	neg edx
@@:
	clc
	ret

NoXYFix:
	stc
	ret

	;each scan line has the following structure
	;0-0eff=scan data
	;0f00-0f79=reserved
	;0f80=hours
	;0f81=minutes
	;0f82=seconds
	;0f83=range
	;0f84=altitude
	;0f85=course made good
	;0f87=crab angle
	;0f88=layback
	;0f8a=scope
	;0f8c=speed in 0.1m/s
	;0f8d=feature flags
	;0f8e=event mark number
	;0f90-0f9a=annotation text
	;0f9b=text position
	;0f9c=cluster number
	;0fc0-0fdf=nav data string

	;0ffe=sounding



UINT:	;THIS IS THE UART interrupt
	;THE DATA byte IS READ FROM THE UART
	;and stored in a temporary buffer ScanBuffer
	;RANGE		SCALE
	;50		1>3
	;75		1>2
	;100		2>3
	;125		5>6
	;150		1>1
	;200		4>3
	;300		2>1
	;400		8>3
	push di 		       ;SAVE THE REGISTERS
	push bx 		       ;TO BE USED
	push ax
	push dx
	mov dx,210h
	in al,dx		       ;get byte from 6402 uart

	mov bx,DNUM		       ;get sample number in bx
	mov dx,LineLength	       ;get scan length
	mov di,20		       ;20 Telemetry bytes in HF
	test RangeNumber,80h
	je @f
	mov di,24		       ;24 Telemetry bytes in LF
@@:
	cmp bx,dx		       ;if there are excess bytes, ingore
	jae UIFin		       ;them
	cmp bx,di		       ;is it telemetry data?
	jb MonDat		       ;if so, jump
	sub bx,di		       ;subtract di to offset telemetry data
	;al now holds 8 bit picture data, bx hold sample number
	mov ah,al
	shl al,1
	or al,LastData
	and ah,1
	mov LastData,ah
	mov di,(offset ScanBuffer+5120)
	cmp bx,10240			;overrun?
	jae UIFin
	shr bx,1
	jc StbdSample1				;jump for starboard sample
	sub di,bx
	dec di
	mov [di],al
	jmp UIFin

StbdSample1:
	add di,bx
	mov [di],al
	jmp UIFin



MonDat:
	dec di
	cmp bx,3			;set range change flag for coax system
	jne @f
	mov RangeChange,1
@@:
	cmp bx,di		       ;is it the last byte of Telemetry data
	jne @f
	and AlarmFlag,0feh	       ;kill 'fish stopped' alarm
	mov TelemetryReady,01H
@@:
	mov TelemetryData[bx],AL	       ;store the monitor data

UIFIN:
	inc dnum
	mov al,030h		       ;RESTART TIMER EACH TIME A NEW
	out 043h,al		       ;byte IS RECIEVED FROM
	mov al,200		       ;THE UART
	out 040h,al		       ;IF 100uS ELAPSES BEFORE THE NEXT
	mov al,5		       ;BYTE, A `END OF SCAN` interrupt
	out 040h,al		       ;WILL BE GENERATED (TINT)
	mov al,(DOSINTMASK AND 0feh)	;switch on timeout interrupts
	out 021h,al
	mov al,020h		       ;SIGNAL interrupt SERVICED
	out 020h,al
	pop dx
	pop ax
	pop bx
	pop di
	iret			       ;RETURN FROM UINT



Com13Int:
	;a byte has been received from COM1

	;MOUSE MOVEMENT interrupt
	;called if COM1 recieves data from the microsoft compatible mouse
	;data is sent as a group of three bytes
	;the first shows the buttons
	;the second is the x displacement and the third is
	;the y displacement

	push DX 		       ;save used registers
	push AX
	mov AL,020H		       ;SIGNAL interrupt SERVICED
	out 020H,AL
	sti
	push cx
	cmp PS2Mouse,1
	je MIFin
	mov DX,03F8H		       ;address of com1
	IN AL,DX		       ;get data
	test AL,040H		       ;is it the first byte in a group?
	jne FMBYTE		       ;if so, jump

	test MOUSEF,040H	       ;whats this?
	je MIFIN
	;EITHER X or Y COORDINATE NOW
	mov cl,MouseRate
	test MOUSEF,080H	       ;test x done flag
	jne MOVEMY		       ;BIT 7 OF MOUSEF=MOVE Y
	;MOVE X HERE
	mov ah,mousef		       ;work out twos complement
	and ah,03h		       ;displacement
	ror ah,2
	or al,ah
	mov ah,al
	test ah,80h		       ;is value negative?
	je @f
	neg ah			       ;find abs
@@:
	inc ah
	imul ah 		       ;ballistic motion
	sar ax,cl		       ;cl holds mouse rate
	add ax,MouseXCoord
	;NOW CHECK LIMITS (0-639)
	cmp ax,5		       ;if x co-ord is<0
	Jge @F
	mov ax,5		       ;set to 0
@@:
	mov dx,635
	test ManualAltitude,1
	je @f
	mov dx,304
@@:
	cmp ax,dx		       ;if x co-ord>639
	Jl @F
	mov ax,dx		       ;set to 639
@@:
	mov MouseXCoord,ax
	or MOUSEF,080H
	JMP MIFIN

MOVEMY:
	mov ah,mousef
	and ah,0ch
	ror ah,4
	or al,ah
	mov ah,al
	test ah,80h		       ;is value negative?
	je @f
	neg ah			       ;find abs
@@:
	inc ah
	imul ah 		       ;ballistic motion
	sar ax,cl
	add ax,MouseYCoord
	;NOW CHECK LIMITS
	cmp ax,5		       ;y<5
	Jge @F
	mov ax,5		       ;if so, set to 5
@@:
	cmp ax,423		       ;y>422
	Jl @F
	mov ax,422		       ;if so, set to 422
@@:
	mov MouseYCoord,ax
	mov MOUSEF,00H
	mov MouseMoved,01H		       ;SIGNAL MOUSE movement
	JMP MIFIN


FMBYTE: ;THE FIRST byte OF A THREE byte CODE COMES HERE
	;*note: buttons are reversed ie. 'RightButton'=1
	;means the left button is down*
	mov RightButton,0
	mov LeftButton,0
	mov MOUSEF,AL		       ;store the button value
	test AL,10H		       ;bit 5 is left hand button
	je @f
	mov LeftButton,01H	       ;if it is down, set BUTTON flag
@@:				       ;otherwise leave it reset
	test al,20h		       ;bit 4 is right hand button
	je mifin
	mov RightButton,01h	       ;if it is down signal button
MIFIN:
	pop cx
	pop AX
	pop DX
	IRET			       ;RETURN FROM Com13Int

RTCInt:
	;real time clock interrupt
	push ax
	sti
	mov al,020h
	out 020h,al
	out 0a0h,al
	mov al,0ch
	out 70h,al
	in al,71h
	test al,10h			;time update?
	je @f
	mov ClockTick,1
@@:
	test al,40h			;periodic update?
	je @f
	mov PeriodTick,1
	inc PTickCount
	push dx
	push bx
	call ScanKeypad		;scan key pad every 1/16 seconds
	pop bx
	pop dx
@@:
	pop ax
	iret

PS2MInt:	;ps/2 mouse interrupt
	push dx
	push ax
	push cx
	in al,60h			;get data byte
	cmp PS2Count,0			;first byte in packet
	je PS2Lab1
	cmp PS2Count,1
	je PS2Lab2
	cmp PS2Count,2
	je PS2Lab3
@@:
	mov PS2Count,0
	jmp PS2Fin


PS2Lab1:
	test al,08h
	je @b
	mov RightButton,0
	mov LeftButton,0
	mov MouseF,al		       ;store the button value
	test al,2		       ;bit 0 is left hand button
	je @f
	mov LeftButton,01H	       ;if it is down, set BUTTON flag
@@:				       ;otherwise leave it reset
	test al,1		       ;bit 1 is right hand button
	je @f
	mov RightButton,01h	       ;if it is down signal button
@@:
	mov PS2Count,1
PS2Fin:
	pop cx
	mov al,020h		       ;SIGNAL interrupt SERVICED
	out 020h,al		       ;to master
	out 0a0h,al		       ;and slave
	pop ax
	pop dx
	IRET			       ;RETURN FROM PS/2 mouse

PS2Lab2:
	;x axis
	mov cl,MouseRate
	mov ah,al
	test ah,80h		       ;negative?
	je @f
	neg ah
@@:
	inc ah
	inc al
	imul ah			       ;ballistic motion
	sar ax,cl		       ;cl holds mouse rate
	add ax,MouseXCoord
	;NOW CHECK LIMITS (0-639)
	cmp ax,5		       ;if x co-ord is<0
	Jge @F
	mov ax,5		       ;set to 0
@@:
	cmp ax,635		       ;if x co-ord>639
	Jl @F
	mov ax,635		       ;set to 639
@@:
	mov MouseXCoord,ax
	mov PS2Count,2
	jmp PS2Fin

PS2Lab3:
	;y axis
	neg al
	mov cl,MouseRate
	mov ah,al
	test ah,80h		       ;negative?
	je @f
	neg ah
@@:
	inc ah
	inc al
	imul ah			       ;ballistic motion
	sar ax,cl
	add ax,MouseYCoord
	;NOW CHECK LIMITS
	cmp ax,5		       ;y<5
	Jge @F
	mov ax,5		       ;if so, set to 5
@@:
	cmp ax,423		       ;y>422
	Jl @F
	mov ax,422		       ;if so, set to 422
@@:
	mov MouseYCoord,ax
	mov PS2Count,0
	mov MouseMoved,01H		       ;SIGNAL MOUSE movement
	jmp PS2Fin



Com24Int:	;nav data interrupt
	;called if COM2 recieves data from the nav interface
	;and stores it in 'NavIntBuffer'
	sti
	push DX 		       ;save used registers
	push AX
	mov AL,020H		       ;SIGNAL interrupt SERVICED
	out 020H,AL

	push si
	mov DX,02F8H		       ;address of com2
	IN AL,DX		       ;get data
	and al,07fh		       ;remove bit 7
	cmp al,13		       ;'CR'? if so, end
	je NavBufferFull

	cmp al,20h		       ;if it is non-printable,
	jb NavIntDone		       ;ignore it

	mov si,NavDataNumber
	cmp si,60		       ;check overflow
	jae NavIntDone
	mov ah,0ffh		       ;terminator
	mov word ptr NavIntBuffer[si],ax	;store it
	inc si
	mov NavDataNumber,si
	jmp NavIntDone

NavBufferFull:
	;if NavDataReady=0
	;copy NavIntBuffer to NavDataBuffer
	;offset NavIntBuffer = offset NavDataBuffer+64
	test NavDataReady,1
	jne DiscardNav			;dont override previous data
	mov si,offset NavIntBuffer
	mov dl,32
@@:
	mov ax,[si]
	add si,2
	mov [si-66],ax		       ;si has been incremented by 2 already
	dec dl
	jnz @b
	mov NavDataReady,1	       ;signal new data ready
DiscardNav:
	mov NavDataNumber,0	       ;reset byte pointer

NavIntDone:
	pop si
	pop AX
	pop DX
	IRET			       ;RETURN FROM Com24Int

kint:	;this is called when ever a key on the PC keyboard is pressed
	push ax
	mov al,20h		       ;signal interupt done
	out 20h,al
	sti
	in al,60h		       ;read data byte
	mov ah,al
	cmp ah,73		       ;intercept Page Up and Page Down
	je PageUp		       ;for lookback scrolling
	cmp ah,81
	je PageDn

	and ah,07fh		       ;remove press/release bit
	cmp ah,42		       ;left shift?
	je ShiftKey1
	cmp ah,54		       ;right shift?
	je ShiftKey1
	test al,80h		       ;release code?
	jne KeyFin		       ;if so, jump
	push bx
	mov bl,ah
	cmp bl,58		       ;is key a function key?
	jbe @f			       ;jump if not
	test ShiftKeyDown,80h	       ;if shift is not down, jump
	je @f
	add bl,30		       ;if it is, add 30 to code
@@:
	mov bh,0		       ;get code from table
	mov ah,PCKeyTran[bx]
	;store code in buffer
	mov bl,KeyBufHead
	mov KeyboardBuffer[bx],ah
	inc bl
	and bl,0fh
	mov KeyBufHead,bl
	pop bx
	jmp KeyFin

PageUp:
	inc UpDownCount
	jmp KeyFin

PageDn:
	dec UpDownCount
	jmp KeyFin


ShiftKey1:
	;come here if a shift key has been pressed or released
	mov ah,al		       ;get original code
	and ah,80h		       ;get press/release bit
	xor ah,80h		       ;invert it
	mov ShiftKeyDown,ah	       ;store it
KeyFin:
	in al,61h		       ;reset keyboard flip-flop
	or al,80h
	out 61h,al
	nop
	nop
	nop
	and al,07fh
	out 61h,al
	pop ax
	iret			       ;return

SetupMouse:
	;set com1 up for 1200-n-7-1
	mov dx,03fbh		       ;set DLAB bit
	mov al,082h
	out dx,al
	mov dx,03f8h		       ;set baud rate to 1200 for mouse
	mov al,060h
	out dx,al
	inc dx
	xor al,al
	out dx,al
	mov dx,03fbh		       ;reset DLAB bit
	mov al,02h
	out dx,al
	inc dx
	mov al,0bh		       ;set DTR and RTS and ints active
	out dx,al
	mov dx,03f9h
	mov al,1
	out dx,al		       ;enable uart interrupts (data received)
	dec dx
	in al,dx
	;set ps/2 mouse
	;check to see if there is a ps/2 mouse port
	IF MOUSEPORT
	cli
	mov al,0a9h
	out 64h,al			;check aux device
	;wait for status byte
@@:
	in al,64h
	test al,01h
	je @b
	in al,60h			;get result
	cmp al,0			;any device?
	jne NoAuxDevice
	mov PS2Mouse,1
	;enable ps/2 mouse
	mov al,0a8h
	out 64h,al
	;
	mov al,0d4h
	out 64h,al
@@:
	in al,64h
	test al,2
	jnz @b
	mov al,0f4h
	out 60h,al
	sti
	ENDIF
	nop
	ret

NoAuxDevice:
	mov PS2Mouse,0
	sti
	ret

SetupRTC:
	;set up RTC
	mov al,0ah		       ;enable 1 second update ints and
	out 70h,al		       ;1/16 second periodic ints on RTC
	mov al,2ch
	out 71h,al

	mov al,0bh
	out 70h,al
	mov al,52h
	out 71h,al
	ret


SetupPulley:
	;set com3 up for 4800-n-8-1
	mov dx,03ebh		       ;set DLAB bit
	mov al,083h
	out dx,al
	mov dx,03e8h		       ;set baud rate to 4800 for pulley
	mov al,018h
	out dx,al
	inc dx
	xor al,al
	out dx,al
	mov dx,03ebh		       ;reset DLAB bit
	mov al,03h
	out dx,al
	inc dx
	mov al,03h		       ;set DTR and RTS
	out dx,al
	mov dx,03e9h
	mov al,0
	out dx,al		       ;disable uart interrupts
	dec dx
	in al,dx
	ret

SetUartBaud:	;set baud rate for com2
	;enter with number between 1 and 5 in al
	;1=1200
	;2=2400
	;3=4800
	;4=9600
	;5=19200
	mov BaudRate,al
	mov cl,al
	mov bx,0c0h
	shr bx,cl
BaudInBX:
	mov dx,02fbh		       ;set DLAB bit
	mov al,083h
	out dx,al
	mov dx,02f8h
	mov al,bl		       ;divider low byte
	out dx,al
	inc dx
	mov al,bh		       ;high byte
	out dx,al
	mov dx,02fbh		       ;reset DLAB bit
	mov al,03h		       ;and set 8 data, 1 stop, no parity
	out dx,al
	inc dx			       ;set DTR and RTS
	mov al,0bh
	out dx,al
	inc dx
	mov al,0
	out dx,al		       ;clear faults
	mov dx,02f9h
	mov al,1
	out dx,al		       ;enable 8520 interrupts
	ret


TInt:	;END OF SCAN HAS BEEN DETECTED
	push ax 		       ;
	mov al,DOSINTMASK	       ;switch off timeout interrupt
	out 021h,al
	mov AL,020H		       ;SIGNAL interrupt SERVICED
	out 020H,AL		       ;
	sti
	mov ax,DNum		       ;get number of bytes in last line
	mov DNum,0000H		       ;reset uart byte number
	mov NewLineLength,ax
	cmp ax,LineLength	       ;compare with current line length
	je @f			       ;if it is the same, jump
	push bx 		       ;
	call CalcNewRange	       ;CALCULATE NEW RANGE
	pop bx			       ;
	jmp Reject		       ;and reject the current line
@@:				       ;come here if there is no range change
	;now scale the data from 'ScanBuffer' into the scan line 'CLine'
	push gs
	push di
	push si
	push cx
	mov ax,CLine
	shl ax,3
	add ax,38h
	mov gs,ax
	mov al,RangeNumber
	and al,0fh
	cmp al,0
	je ScaleFor50
	cmp al,1
	je ScaleFor100
	cmp al,8
	je ScaleFor100
	cmp al,2
	je ScaleFor125
	cmp al,3
	je ScaleFor150
	cmp al,4
	je ScaleFor200
	cmp al,5
	je ScaleFor300
	cmp al,6
	je ScaleFor400
	cmp al,7
	je ScaleFor75
	jmp ScalingDone

ScaleFor50:
	;scale for 50m 1>3
	mov si,(offset ScanBuffer+4480)
	xor di,di
	mov cx,1280
@@:
	mov al,[si]
	mov ah,al
	mov gs:[di],ax
	mov gs:[di+2],al
	add di,3
	inc si
	loop @b
	jmp ScalingDone

ScaleFor100:
	;scale for 100m 2>3
	mov si,(offset ScanBuffer+3840)
	xor di,di
	mov cx,1280
@@:
	mov ax,[si]
	mov gs:[di],al
	add al,ah
	rcr al,1
	mov gs:[di+1],ax
	add di,3
	add si,2
	loop @b
	jmp ScalingDone

ScaleFor125:
	;scale for 125m 5>6
	mov si,(offset ScanBuffer+3520)
	xor di,di
	mov cx,640
@@:
	mov ax,[si]
	mov gs:[di],ax
	mov ax,[si+2]
	mov gs:[di+2],ax
	mov al,[si+4]
	add ah,al
	rcr ah,1
	xchg al,ah
	mov gs:[di+4],ax
	add di,6
	add si,5
	loop @b
	jmp ScalingDone

ScaleFor150:
	;scale for 150m 1>1
	mov si,(offset ScanBuffer+3200)
	xor di,di
	mov cx,1920
@@:
	mov ax,[si]
	mov gs:[di],ax
	add di,2
	add si,2
	loop @b
	jmp ScalingDone

ScaleFor200:
	;scale for 200m 4>3
	mov si,(offset ScanBuffer+2560)
	xor di,di
	mov cx,1280
@@:
	mov ax,[si]
	mov gs:[di],ax
	mov ax,[si]
	add al,ah
	rcr al,1
	mov gs:[di],al
	add di,3
	add si,4
	loop @b
	jmp ScalingDone

ScaleFor300:
	;scale for 300m 2>1
	mov si,(offset ScanBuffer+1280)
	xor di,di
	mov cx,3840
@@:
	mov ax,[si]
	add al,ah
	rcr al,1
	mov gs:[di],al
	inc di
	add si,2
	loop @b
	jmp ScalingDone

ScaleFor400:
	;scale for 400m 8>3
	mov si,offset ScanBuffer
	xor di,di
	mov cx,1280
@@:
	mov ax,[si]
	add al,ah
	rcr al,1
	mov gs:[di],al
	mov ax,[si+3]
	add al,ah
	rcr al,1
	mov gs:[di+1],al
	mov ax,[si+6]
	add al,ah
	rcr al,1
	mov gs:[di+2],al
	add si,8
	add di,3
	loop @b
	jmp ScalingDone

ScaleFor75:
	;scale for 70m 1>2
	mov si,(offset ScanBuffer+4160)
	xor di,di
	mov cx,1920
@@:
	mov al,[si]
	mov ah,al
	mov gs:[di],ax
	add di,2
	inc si
	loop @b
	jmp ScalingDone


ScalingDone:
	;fill in data fields
	mov ah,Hours
	mov gs:[0f80h],ah	       ;time
	mov ah,Minutes
	mov gs:[0f81h],ah
	mov ah,Seconds
	mov gs:[0f82h],ah
	mov ah,RangeNumber
	mov gs:[0f83h],ah	       ;range
	mov ah,Altitude
	mov GS:[0f84H],AH	       ;altitude
	mov ax,NavCourse
	mov gs:[0f85h],ax	       ;course
	mov ah,NavAngle
	mov gs:[0f87h],ah	       ;crab angle
	mov ax,NavLayback
	mov gs:[0f88h],ax	       ;layback
	mov ax,CableScope
	mov gs:[0f8ah],ax	       ;scope
	mov ah,Speed
	mov gs:[0f8ch],ah	       ;speed
	mov ax,Sounding
	mov gs:[0ffeh],ax	       ;depth sounding

	;now the feature flags are processed
	;if the line is a non-cue line:
	;  if there is a feature, store it in 0f8dh
	;  and set SkippedFlag to 20h
	;if the line is a cue line:
	;  if there is a feature, store it in 0f8dh
	;  do not set SkippedFlag (don't reset it either)

	test FeatureFlag,08h	       ;does nav data need to be recorded?
	je DontRecNav		       ;if not, jump
	;the data in 'CompNavString' is copied into the
	;32 bytes gs:[fc0h-fdfh]
	mov di,0fc0h
	mov si,offset CompNavString
	mov cl,16
@@:
	mov ax,[si]
	mov gs:[di],ax
	add si,2
	add di,2
	dec cl
	jnz @b
DontRecNav:
	mov ah,FeatureFlag	       ;get the feature request flag in ah
	test ah,01h		       ;is there an event mark?
	je DontRecVMark		       ;if not, jump ahead
	mov ax,EventNumber	       ;if so, store event mark number
	mov gs:[0f8eh],ax	       ;in gs:[0f8eh]
	inc al			       ;increment event number
	daa			       ;its in BCD
	xchg al,ah
	jnc @f
	add al,1
	daa
@@:
	xchg al,ah
	mov EventNumber,ax
DontRecVMark:
	;now see if the line is a cue line
	mov ah,FeatureFlag
	inc CueLineCount	       ;every fourth line is a Cue line
	cmp CueLineCount,4	       ;ie. it is displayed when Cue mode
	jne NotACueLine 	       ;is active

	;the line is a cue line
	mov CueLineCount,0	       ;bit 4 (010h) of 0f8dh in the line
	or ah,010h		       ;is set to mark it as a cue line
	or ah,SkippedFlag	       ;get flag in ah
	mov SkippedFlag,00H	       ;clear flag for next time
	jmp @f

NotACueLine:
	test ah,0c7h		       ;is there a feature? (apart from nav)
	je @f
	mov SkippedFlag,20h	       ;if there is, set the flag
@@:
	;the flags are now done
	mov gs:[0f8dh],ah	       ;store the feature flag
	mov FeatureFlag,0	       ;reset it

	pop cx
	pop si
	pop di
	pop gs

	mov ax,CLine		       ;advance the current line,
	inc ax			       ;wrapping round if needed
	and ax,BufferLimit
	mov CLine,ax		       ;store new current line number

	mov SonarIsOn,01H	       ;towfish is running
Reject:
	inc HBoxC		       ;altitude box counter
	jnz @f
	mov HBoxReady,1
@@:
	pop AX			       ;RESTORE AX
	IRET			       ;RETURN FROM TINT


ClearMainBuffer:


	;THIS FILLS THE BUFFER with the pattern in 'CMAXLogo'
	mov BP,0038H			;starting selector
	mov ch,0			;stagger control
	mov dl,27			;line in logo
FTB2:
	mov GS,BP
	mov eax,0
	xor di,di
@@:
	mov gs:[di],eax
	add di,4
	;add eax,01010101h
	cmp di,3840
	jnz @b

	;fill in other stuff
	mov bx,0f80h
	mov byte ptr gs:[bx+3],0	;set empty lines to 50m HF
	mov byte ptr gs:[bx+4],255	;set altidude to MAX
	mov byte ptr gs:[bx+12],15	;speed=1.5m/s
	mov byte ptr gs:[bx+13],0	;no features

	add BP,08H
	cmp bp,LastSelector
	jne FTB2
	ret
	xor di,di
CMB3:
	movzx si,dl
	shl si,4			;address in logo is 16*line
	test ch,1
	je @f
	add si,8
@@:
	mov dh,15			;repeats 7.5 times (960/128)
	mov bl,4
CMB2:
	IFE MICREL
	mov eax,dword ptr fs:CMAXLogo[si]
	ELSE
	xor eax,eax
	ENDIF

	IF DOS
	bswap eax
	ELSE
	xchg al,ah
	rol eax,16
	xchg al,ah
	ENDIF
	mov cl,32			;4*32 pixels
CMB1:
	mov bh,0
	rol eax,1
	jnc @f
	mov bh,80h
@@:
	or gs:[di],bh
	inc di
	dec cl
	jnz CMB1
	cmp di,960
	je CMB5
	add si,4
	test si,0fh
	jne @f
	sub si,10h
@@:
	dec bl
	jnz CMB2
	jmp CMB3
CMB5:
	sub dl,1
	jnc @f
	xor ch,1
	mov dl,27
@@:
	;fill in other stuff
	mov bx,0f80h
	mov byte ptr gs:[bx+3],0	;set empty lines to 50m HF
	mov byte ptr gs:[bx+4],255	;set altidude to MAX
	mov byte ptr gs:[bx+12],15	;speed=1.5m/s
	mov byte ptr gs:[bx+13],0	;no features

	add BP,08H
	cmp bp,LastSelector
	jne FTB2
	ret



ReadNewSoft:
	;reads 64k into pseg from clusters 0-15
	call SELECT		       ;SELECT THE DRIVE
	mov ax,4880h
	mov edx,8
	cmp MediaType,2
	jne @f
	mov ax,4820h
	mov edx,2
@@:
	call SCSICommand
	mov ax,30h
	push ds
	mov ds,ax
	mov cx,0
	mov si,0
	call ReadCXData
	pop ds
	call SCSIStatus
	call SCSIMessage
	clc
	RET


READS:	;SELECTS and ISSUES A READ SECTor COMMAND
	;READS THE STATUS and MESSAGE
	test ReadFormat,1
	jne ReadOld
	push DX
	call SELECT		       ;SELECT THE DRIVE
	mov ax,0808h
	cmp MediaType,2
	jne @f
	mov ax,0802h
@@:
	call SCSICommand
	pop DX
	jc diskError
	call REaddT
	call SCSIStatus
	call SCSIMessage
	clc
	ret


ReadOld:
	;this reads a 1024 byte scan (v4) and converts it to a 4096 byte
	;V5 scan
	push dx 			;segment in dx
	test CurrentCluster,1		;odd or even
	jne AlreadyLoaded
	call Select
	mov edx,CurrentCluster
	add edx,4
	shl edx,1
	mov ax,4804h
	cmp MediaType,2
	jne @f
	mov ax,4801h
	shr edx,2
@@:
	call SCSICommand
	mov cx,2048
	mov si,offset ConvertBuffer
	call ReadCXData 		;read 2048 bytes (2 scans) into
	call SCSIStatus 		;into ConvertBuffer
	call SCSIMessage
	mov dx,0
	jmp @f
AlreadyLoaded:
	mov dx,1024
@@:
	;now convert to V5
	pop ax
	shl ax,3
	add ax,038h
	mov gs,ax			;destination segment
	;first expand data
	mov di,1920
	mov si,di
	mov cx,960
@@:
	mov bx,960
	sub bx,cx
	add bx,dx
	mov al,ConvertBuffer[bx]	;gamma adjust
	mov bx,offset OldToNew
	mov ah,al
	and ah,0fh
	shr al,4
	xlatb fs:[OldToNew]
	mov gs:[di],al
	mov gs:[di+1],al
	add di,2
	sub si,2
	mov al,ah
	xlatb fs:[OldToNew]
	mov gs:[si],al
	mov gs:[si+1],al
	loop @b
	;time
	mov si,(offset ConvertBuffer+03c0h)
	add si,dx
	mov ax,[si]
	mov gs:[0f80h],ax
	mov al,[si+2]
	mov gs:[0f82h],al
	;range
	mov al,[si+3]
	mov ah,0
	cmp al,0
	je @f
	mov ah,1
	cmp al,2
	je @f
	mov ah,2
	cmp al,4
	je @f
	mov ah,3
	cmp al,3
	je @f
	mov ah,84h
	cmp al,82h
	je @f
	mov ah,85h
	cmp al,83h
	je @f
	mov ah,81h
	cmp al,80h
	je @f
	mov ah,1
@@:
	mov gs:[0f83h],ah
	;altitude
	mov al,[si+4]
	test ReadFormat,2
	jne @f
	shr al,1
@@:
	mov gs:[0f84h],al
	;feature flag
	mov al,[si+6]
	mov gs:[0f8dh],al
	;annotation
	mov al,[si+8]
	mov gs:[0f9bh],al
	mov eax,[si+9]
	mov gs:[0f90h],eax
	mov eax,[si+13]
	mov gs:[0f94h],eax
	mov ax,[si+17]
	mov gs:[0f98h],ax
	mov byte ptr gs:[0f9ah],0ffh
	;speed
	mov al,[si+5]
	mov gs:[0f8ch],al
	;event mark no.
	mov al,[si+7]
	mov ah,[si+22]
	mov gs:[0f8eh],ax
	;heading
	mov ax,[si+30]
	mov gs:[0f85h],ax
	;nav data
	mov di,0fc0h
	mov si,3e0h
	add si,dx
	mov cx,32
@@:
	mov al,ConvertBuffer[si]
	mov gs:[di],al
	inc si
	inc di
	loop @b
	clc
	ret


CheckHour:
	;checks if the value in al is a valid hour
	mov ah,al
	and ah,0f0h
	and al,0fh
	cmp ah,20h
	ja NotHour
	jne @f
	cmp al,03h
	ja NotHour
@@:
	cmp al,09h
	ja NotHour
	clc
	ret
NotHour:
	stc
	ret


WRITES:
	;SELECTS and ISSUES A WRITE cluster COMMAND
	;READS THE STATUS and MESSAGE
	;THE DATA COMES FROM THE SCAN SEGMENT DX
	push DX
	call SELECT
	mov ax,0a08h
	cmp MediaType,2
	jne @f
	mov ax,0a02h
@@:
	call SCSICommand
	pop DX
	call WRITDT
	call SCSIStatus
	call SCSIMessage
	RET

WriteNewAlt:
	;this writes 31 clusters to the disk at edx from segment di
	add edx,4		       ;SKIP DIRECTORY
	shl edx,3		       ;8 sectors per cluster
	cmp MediaType,2
	jne @f
	shr edx,2		       ;2 if disk is 640
@@:
	push di
	push edx
	call SELECT
	pop edx
	mov ax,04af8h			;0f8h=248=31*8 for 128mb & 230mb
	cmp MediaType,2
	jne @f
	mov ax,04a3eh			;03eh=62=31*2 for 640mb
@@:
	call SCSICommand
	mov EditSize,31
	pop di
	call WriteEditData
	call SCSIStatus
	call SCSIMessage
	RET

Write16:
	;SELECTS and ISSUES A WRITE cluster COMMAND
	;READS THE STATUS and MESSAGE
	;THE DATA COMES FROM THE SCAN SEGMENT DX
	mov TroubleSelector,0ffffh
	mov RetryCount,3
	mov TempWSegment,dx
	mov eax,CurrentCluster
	mov TempWCluster,eax
WRetry1:
	push DX
	call SELECT
	mov ax,0a80h
	cmp MediaType,2
	jne @f
	mov ax,0a20h
@@:
	call SCSICommand
	pop DX
	jc Write16Error
	call Wrt16Data
	jc WriteRetry
	call SCSIStatus
	call SCSIMessage
	clc
	RET

WriteRetry:
	mov eax,TempWCluster
	mov CurrentCluster,eax
	mov dx,TempWSegment
	dec RetryCount
	jnz WRetry1
Write16Error:
	stc
	ret


diskError:
	call SCSIStatus
	call SCSIMessage
	mov StorageMode,0
	call StatusMode
	mov si,offset ErrorMsg16       ;'disk error'
	call Rebuke
	stc
	ret

WriteEditClusters:

	;this writes the visible part of the main buffer
	;for 'edit'
	call select		       ;select the drive
	mov si,offset SCSI10Command	;address of command
	mov byte ptr [si],02ah		;ten byte write
	mov ax,EditSize 	       ;get number of lines
	shl ax,3		       ;number of sectors
	cmp MediaType,2
	jne @f
	shr ax,2
@@:
	mov [si+7],ah		       ;insert this into the command
	mov [si+8],al
	call TenByteCommand	       ;issue the command
	mov di,ScreenLineMap[850]	;start segment
	call WriteEditData	       ;output the data
	call SCSIStatus		       ;get status
	call SCSIMessage	       ;and message
	ret			       ;finished

LDIRS:	;reads the directory sectors
	call SELECT		       ;SELECT THE DRIVE
	mov ax,08808h
	cmp MediaType,2
	jne @f
	mov ax,08802h
@@:
	call SCSICommand		       ;ISSUE COMMAND
	jc diskError
	mov cx,4096
	mov si,offset dirsec
	call ReadCXData
	call SCSIStatus
	call SCSIMessage
	mov si,offset DirSec
	test byte ptr [si],0e0h
	jne @f
	clc
	RET
@@:
	stc
	ret

LSSEC:	;reads a sector into srchbf
	test ReadFormat,1
	jne OldSearch
	call SELECT		       ;SELECT THE DRIVE
	mov ax,0808h
	cmp MediaType,2
	jne @f
	mov ax,0802h
@@:
	call SCSICommand		       ;ISSUE COMMAND
	mov cx,4096
	mov si,offset srchbf
	call ReadCXData
	call SCSIStatus
	call SCSIMessage
	RET

OldSearch:
	call Select
	mov edx,CurrentCluster
	add edx,4
	shl edx,1
	mov ax,4804h
	cmp MediaType,2
	jne @f
	mov ax,4801h
	shr edx,2
@@:
	call SCSICommand
	mov cx,2048
	mov si,offset srchbf
	call ReadCXData 		;read 2048 bytes (2 scans) into
	call SCSIStatus 		;into srchbf
	call SCSIMessage
	;only convert the time
	mov si,offset srchbf
	mov ax,[si+03c0h]
	mov [si+0f80h],ax
	mov al,[si+03c2h]
	mov [si+0f82h],al
	ret


WDIRS:	;writes the directory cluster
	call SELECT		       ;SELECT THE DRIVE
	mov ax,8a08h
	cmp MediaType,2
	jne @f
	mov ax,8a02h
@@:
	call SCSICommand		       ;ISSUE COMMAND
	jc diskError
	call WRTDIR
	call SCSIStatus
	call SCSIMessage
	mov AL,00H		       ;SUCCESS
	RET

WDIRE:	;AN ERRor HAS BEEN FOUND
	call SCSIStatus
	call SCSIMessage
	call RSENSE
	mov si,offset ErrorMsg16       ;'disk error'
	call Rebuke
	mov AL,01H		       ;SIGNAL ERROR
	RET

RSENSE: ;SELECTS and ISSUES A REQUEST SENSE COMMAND
	;stores the sense data in rsbuff
	call SELECT		       ;SELECT THE SONAR
	jnc @f
	ret			       ;drop out if no drive is found
@@:
	mov ax,8312h
	call SCSICommand
	mov cx,18
	mov si,offset rsbuff
	call ReadCXData
	call SCSIStatus
	call SCSIMessage
	RET

EJECTD: ;EJECTS THE disk
	;call ALMERE		       ;ALLOW MEDIUM REMOVAL
	call SELECT
	mov ax,9b02h
	call SCSICommand
	call SCSIStatus
	call SCSIMessage
	RET

PRMERE: ;PREVENTS MEDIUM REMOVAL
	ret

ALMERE: ;ALLOWS MEDIUM REMOVAL
	call SELECT
	mov ax,9e00h
	call SCSICommand
	call SCSIStatus
	call SCSIMessage
	RET

TestUnitReady: ;test UNIT READY For DRIVE
	call SELECT
	mov ax,8000h
	call SCSICommand
	call SCSIStatus
	mov DSTAT,BL		       ;STORE STATUS
	call SCSIMessage
	RET

GetMediaSize:
	call Select
	mov ax,04b00h
	mov edx,60000h
	call SCSICommand
	call SCSIStatus
	mov DStat,bl
	call SCSIMessage
	cmp DStat,0
	mov al,1			;medium is 230Mb
	je @f
	call Select
	mov ax,04b00h
	mov edx,48000h
	call SCSICommand
	call SCSIStatus
	mov DStat,bl
	call SCSIMessage
	cmp DStat,0
	mov al,2			;medium is 640Mb
	je @f
	mov al,0			;medium is 128Mb
@@:
	mov MediaType,al
	ret


VerifyForRead: ;checks if a disc is in the drive
	;and if so, determines its capacity
	call TestUnitReady	       ;test UNIT READY
	cmp DSTAT,00H		       ;IS STATUS GOOD
	je @f				;JUMP IF SO
	call RSENSE		       ;IF NOT, REQUEST SENSE
	call TestUnitReady	       ;and test AGAIN
	cmp DSTAT,00H
	je @f
	stc			       ;not ready
	RET

@@:
	;see what media type is installed 128, 230 or 640Mb
	;try and read a sector past 128MB
	call GetMediaSize
	clc				;ready
	RET


VerifyForWrite:
	;this gets the status of the write-protect tab on the disk
	;using a mode sense command
	;it reads code page 20h which returns the disk capacity
	;it is called from 'edit', 'record' and 'fix annotation'
	call select		       ;select the device
	mov ax,09a04h
	call SCSICommand
	mov cx,4
	mov si,offset ModeSenseBuffer
	call ReadCXData			;read 18h bytes
	call SCSIStatus
	call SCSIMessage
	mov al,ModeSenseBuffer[2]      ;get write protect bit
	and al,080h		       ;set zero flag
	je @f
	ret

@@:
	call GetMediaSize
	xor al,al
	ret



SELECT: ;ALLOWS SONAR TO GAIN CONTROL OF THE SCSI BUS
	;and CHANGES PHASE TO COMMAND
	mov DX,SCSIReg2		       ;INITIALISE INTERRUPT CONDITIONS
	mov AL,00H
	out DX,AL

	mov cl,1
	cmp SCSIID,0
	je @f
	mov cl,SCSIID
@@:
	mov DX,SCSIReg3
	mov AL,00H
	out DX,AL
	inc DX
@@:
	IN AL,DX
	test AL,040H		       ;WAIT For BUS FREE
	jnz @B
TryAgain:
	mov AL,cl		       ;SET ID
	mov DX,SCSIReg0
	out DX,AL

	mov DX,SCSIReg1		       ;ASSERT SEL & ENABLE O/P SCSI DATA
	mov AL,05H
	out DX,AL

	mov di,4000h
	mov DX,SCSIReg4		       ;WAIT For BUSY TO GO ACTIVE
@@:
	dec di
	jz NoSelect
	IN AL,DX
	test AL,040H
	jz @B
	mov SCSIID,cl
	mov DX,SCSIReg1		       ;DEASSERT SEL & ENABLE O/P SCSI DATA
	mov AL,01H
	out DX,AL

	mov DX,SCSIReg4			;WAIT For COMMand PHASE
@@:
	IN AL,DX
	and AL,01CH
	cmp AL,08H
	jnz @B

	mov DX,SCSIReg3			;ASSERT COMMand PHASE
	mov AL,02H
	out DX,AL

	mov DX,SCSIReg7			;CLEAR interrupt FLAGS
	IN AL,DX

	mov DX,SCSIReg1			;ASSERT OUTPUT
	mov AL,01H
	out DX,AL
	clc
	RET
NoSelect:
	mov DX,SCSIReg1		       ;de-ASSERT SEL & ENABLE O/P SCSI DATA
	mov AL,0
	out DX,AL

	shl cl,1
	jnc TryAgain
	mov DriveError,1
	ret


SCSICommand:;sends the command (6 byte) in ah, count in al
	;if bit 7 of ah is set, zero cluster
	;if bit 6 of ah is set, take sector from edx
	;otherwise cluster is from CurrentCluster
	mov si,offset SCSI6Command
	mov bl,ah
	and ah,3fh
	mov [si],ah			;command
	mov [si+4],al			;count
	xor eax,eax
	test bl,80h
	jne @f
	mov eax,edx
	test bl,40h
	jne @f

	mov EAX,CurrentCluster
	add EAX,4		       ;SKIP DIRECTORY
	shl EAX,3		       ;8 sectors per cluster
	cmp MediaType,2
	jne @f
	shr eax,2		       ;2 if disk is 640
@@:
	mov [SI+2],AH
	mov [SI+3],AL
	shr EAX,8
	mov [SI+1],AH

	mov BL,6		       ;COUNT For COMMand BYTES
COMLP:
	mov DX,SCSIReg0
	mov AL,[SI]		       ;READ COMMand byte FROM TABLE
	out DX,AL		       ;SET UP READ COMMAND
	inc SI			       ;INCREASE POINTER

@@:
	mov DX,SCSIReg4		       ;WAIT For ASSERT REQ
	IN AL,DX
	test AL,20H
	jz @B

	mov DX,SCSIReg1		       ;ASSERT ACK
	mov AL,11H
	out DX,AL

@@:
	mov DX,SCSIReg4		       ;WAIT For DEASSERT REQ
	IN AL,DX
	test AL,20H
	jnz @B


	mov DX,SCSIReg1		       ;DEASSERT ACK
	mov AL,01H
	out DX,AL

	dec BL			       ;DECREASE COMMand COUNTER
	jnz COMLP		       ;LOOP BACK IF NOT ZERO

	mov DX,SCSIReg1		       ;DEASSERT BUS
	mov AL,00H
	out DX,AL
	;now see what phase comes next
	;wait for data in, data out or status
@@:
	mov DX,SCSIReg4
	IN AL,DX
	and AL,01CH
	cmp AL,08H		       ;still in command phase
	je @B
	mov al,10
@@:
	dec al
	jnz @b
	in al,dx
	and al,01ch
	cmp al,0ch		       ;status phase?
	je @f
	clc
	RET
@@:
	stc
	ret

TenByteCommand:
	;sends a ten byte command at [si] to the scsi unit
	;the cluster number is added at [si+2]
	mov EAX,CurrentCluster
	add EAX,4		       ;SKIP DIRECTORY
	shl EAX,3		       ;8 sectors per cluster
	cmp MediaType,2
	jne @f
	shr eax,2
@@:
	mov [SI+4],AH		       ;get sector number
	mov [SI+5],AL
	shr EAX,16
	mov [SI+2],AH
	mov [si+3],al

	mov BL,10		       ;COUNT For COMMand BYTES
	jmp comlp

SCSIStatus: ;TO BE CALLED AFTER FINAL BLOCK IS RECEIVED TO CHECK STATUS


@@:				       ;WAIT For STATUS PHASE
	mov DX,SCSIReg4
	IN AL,DX
	and AL,01CH
	cmp AL,0CH
	jne @B

	mov DX,SCSIReg3		       ;ASSERT STATUS PHASE
	mov AL,3
	out DX,AL

	mov DX,SCSIReg4		       ;WAIT For ASSERT REQ
@@:
	IN AL,DX
	test AL,20H
	jz @B

	mov DX,SCSIReg0		       ;READ STATUS BYTE
	IN AL,DX
	mov BL,AL

	mov DX,SCSIReg1		       ;ASSERT ACK
	mov AL,10H
	out DX,AL

	mov DX,SCSIReg4		       ;WAIT For DEASSERT REQ
@@:
	IN AL,DX
	test AL,20H
	jnz @B

	mov DX,SCSIReg1		       ;DEASSERT ACK
	mov AL,00H
	out DX,AL

	RET

SCSIMessage:;TO BE CALLED AFTER FINAL BLOCK IS RECEIVED TO CHECK MESSAGE
@@:				       ;WAIT For MESSAGE PHASE
	mov DX,SCSIReg4
	IN AL,DX
	and AL,01CH
	cmp AL,01CH
	jne @B

	mov DX,SCSIReg3		       ;ASSERT MESSAGE PHASE
	mov AL,7
	out DX,AL

	mov DX,SCSIReg4		       ;WAIT For ASSERT REQ
@@:
	IN AL,DX
	test AL,20H
	jz @B

	mov DX,SCSIReg0		       ;READ MESSAGE BYTE
	IN AL,DX

	mov DX,SCSIReg1		       ;ASSERT ACK
	mov AL,10H
	out DX,AL

	mov DX,SCSIReg4		       ;WAIT For DEASSERT REQ
@@:
	IN AL,DX
	test AL,20H
	jnz @B

	mov DX,SCSIReg1		       ;DEASSERT ACK
	mov AL,00H
	out DX,AL

	RET


WriteEditData:
	;Writes the visible screen sectors

	mov DX,SCSIReg1		       ;ASSERT BUS
	mov AL,01H
	out DX,AL

	mov DX,SCSIReg4
@@:				       ;WAIT For DATA out PHASE
	IN AL,DX
	and AL,01CH
	cmp AL,00H
	jne @B

	mov DX,SCSIReg3
	mov AL,00H
	out DX,AL		       ;ASSERT DATA out PHASE

	mov bx,EditSize		       ;number of clusters to be written

WriteEditD2:
	;now write the data
	mov ax,di		       ;the segment is in di
	shl ax,3
	add ax,038H
	mov GS,ax

	mov CX,4096		       ;write 4096 bytes from each segment
	mov SI,0
WriteEditD1:

	mov DX,SCSIReg4		       ;WAIT For ASSERT REQ
@@:
	IN AL,DX
	test AL,20H
	jz @B

	mov AL,GS:[SI]
	mov DX,SCSIReg0
	out DX,AL
	inc SI


	mov DX,SCSIReg1		       ;ASSERT ACK
	mov AL,11H
	out DX,AL

	mov DX,SCSIReg4		       ;WAIT For DEASSERT REQ
@@:
	IN AL,DX
	test AL,20H
	jnz @B

	mov DX,SCSIReg1		       ;DEASSERT ACK
	mov AL,01H
	out DX,AL

	LOOP WriteEditD1

	inc di			       ;increase segment
	and di,BufferLimit	       ;wrap round
	dec bx			       ;decrement segment counter
	jnz WriteEditD2
	RET

Wrt16Data: ;WRITES 65536 BYTES TO 128 SECTORS

	shl DX,3
	add DX,038H
	mov BP,DX
	mov bl,RecordChunk
LF16sec2:
	mov GS,BP		       ;segment in bp
	;first tag the line with the cluster number
	mov eax,CurrentCluster
	mov gs:[0f9ch],eax
	inc eax
	mov CurrentCluster,eax
	mov DX,SCSIReg1		       ;ASSERT BUS
	mov AL,01H
	out DX,AL

	mov DX,SCSIReg4
@@:				       ;WAIT For DATA out PHASE
	IN AL,DX
	and AL,01CH
	cmp AL,00H
	jne @B

	mov DX,SCSIReg3
	mov AL,00H
	out DX,AL		       ;ASSERT DATA out PHASE

	mov CX,4096
	mov SI,0
LF16SEC1:
	mov di,0
	mov DX,SCSIReg4		       ;WAIT For ASSERT REQ
@@:
	dec di
	jz Disconnect
	IN AL,DX
	test AL,20H
	jz @B


	mov AL,GS:[SI]		       ;send data
	mov DX,SCSIReg0
	out DX,AL
	inc SI

	mov DX,SCSIReg1		       ;ASSERT ACK
	mov AL,11H
	out DX,AL

	mov DX,SCSIReg4		       ;WAIT For DEASSERT REQ
@@:
	IN AL,DX
	test AL,20H
	jnz @B

	mov DX,SCSIReg1		       ;DEASSERT ACK
	mov AL,01H
	out DX,AL

	LOOP LF16SEC1
	add bp,8
	cmp bp,LastSelector	       ;wrap round the selector value
	jne @f			       ;in bp
	mov bp,56
@@:
	cmp bp,TroubleSelector
	jne @f
	add bp,8
	cmp bp,LastSelector	       ;wrap round the selector value
	jne @f			       ;in bp
	mov bp,56
@@:
	dec bl
	jnz LF16sec2
	clc
	RET

Disconnect:
	;re-issue the command
	mov TroubleSelector,bp
	stc
	ret


WRITDT: ;WRITES 4096 BYTES TO 8 SECTORS

	shl DX,3
	add DX,038H
	mov BP,DX
	mov GS,BP

	mov DX,SCSIReg1		       ;ASSERT BUS
	mov AL,01H
	out DX,AL

	mov DX,SCSIReg4
@@:				       ;WAIT For DATA out PHASE
	IN AL,DX
	and AL,01CH
	cmp AL,00H
	jne @B

	mov DX,SCSIReg3
	mov AL,00H
	out DX,AL		       ;ASSERT DATA out PHASE

	mov CX,4096
	mov SI,0
LFSEC:
	mov DX,SCSIReg4		       ;WAIT For ASSERT REQ
@@:
	IN AL,DX
	test AL,20H
	jz @B


	mov AL,GS:[SI]
	mov DX,SCSIReg0
	out DX,AL
	inc SI

	mov DX,SCSIReg1		       ;ASSERT ACK
	mov AL,11H
	out DX,AL

	mov DX,SCSIReg4		       ;WAIT For DEASSERT REQ
@@:
	IN AL,DX
	test AL,20H
	jnz @B

	mov DX,SCSIReg1		       ;DEASSERT ACK
	mov AL,01H
	out DX,AL

	LOOP LFSEC

	RET

REaddT: ;READS 4096 BYTES FROM 8 SECTORS

	shl DX,3
	add DX,038H
	mov BP,DX
	mov GS,BP

	mov DX,SCSIReg1		       ;DEASSERT BUS
	mov AL,00H
	out DX,AL

	mov DX,SCSIReg4
@@:				       ;WAIT For DATA IN PHASE
	IN AL,DX
	and AL,01CH
	cmp AL,04H
	jne @B

	mov DX,SCSIReg3
	mov AL,01H
	out DX,AL		       ;ASSERT DATA out PHASE

	mov CX,4096
	mov SI,0
RESEC:
	mov DX,SCSIReg4		       ;WAIT For ASSERT REQ
@@:
	IN AL,DX
	test AL,20H
	jz @B
	mov DX,SCSIReg0
	IN AL,DX

	mov GS:[SI],AL
	inc SI

	mov DX,SCSIReg1		       ;ASSERT ACK
	mov AL,10H
	out DX,AL
	mov DX,SCSIReg4		       ;WAIT For DEASSERT REQ
@@:
	IN AL,DX
	test AL,20H
	jnz @B

	mov DX,SCSIReg1		       ;DEASSERT ACK
	mov AL,00H
	out DX,AL

	LOOP RESEC

	RET


ReadCXData:
	;reads CX bytes into ds:[si]
	mov DX,SCSIReg1		       ;DEASSERT BUS
	mov AL,00H
	out DX,AL
	mov DX,SCSIReg4
@@:				       ;WAIT For DATA out PHASE
	IN AL,DX
	and AL,01CH
	cmp AL,04H
	jne @B
	mov DX,SCSIReg3
	mov AL,01H
	out DX,AL		       ;ASSERT DATA out PHASE
CXData1:
	mov DX,SCSIReg4		       ;WAIT For ASSERT REQ
@@:
	IN AL,DX
	test AL,20H
	jz @B
	mov DX,SCSIReg0 	       ;read data
	IN AL,DX
	mov [SI],AL
	inc SI
	mov DX,SCSIReg1		       ;ASSERT ACK
	mov AL,10H
	out DX,AL
	mov DX,SCSIReg4		       ;WAIT For DEASSERT REQ
@@:
	IN AL,DX
	test AL,20H
	jnz @B
	mov DX,SCSIReg1		       ;DEASSERT ACK
	mov AL,00H
	out DX,AL
	LOOP CXData1
	RET

WRTDIR: ;WRITES 4096 BYTES TO TWO SECTORS
	mov DX,SCSIReg1		       ;ASSERT BUS
	mov AL,01H
	out DX,AL
	mov DX,SCSIReg4
@@:				       ;WAIT For DATA out PHASE
	IN AL,DX
	and AL,01CH
	cmp AL,00H
	jne @B

	mov DX,SCSIReg3
	mov AL,00H
	out DX,AL		       ;ASSERT DATA out PHASE

	mov CX,4096
	mov SI,offset DIRSEC
WDSEC:
	mov DX,SCSIReg4		       ;WAIT For ASSERT REQ
@@:
	IN AL,DX
	test AL,20H
	jz @B
	mov AL,[SI]
	mov DX,SCSIReg0
	out DX,AL
	inc SI
	mov DX,SCSIReg1		       ;ASSERT ACK
	mov AL,11H
	out DX,AL
	mov DX,SCSIReg4		       ;WAIT For DEASSERT REQ
@@:
	IN AL,DX
	test AL,20H
	jnz @B
	mov DX,SCSIReg1		       ;DEASSERT ACK
	mov AL,01H
	out DX,AL
	LOOP WDSEC
	RET

SRESET: ;RESETS SCSI BUS and CONTROLLER
	mov DX,0211H		       ;RESETS SCSI BUS
	mov AL,CoaxPower
	out DX,AL
@@:
	NOP
	NOP
	NOP
	NOP
	dec al
	jnz @b
	IF NOOFBITS EQ 6
	mov al,6		       ;78bit
	ELSE
	mov al,2
	ENDIF
	or al,CoaxPower
	out DX,AL

	mov DX,0219H		       ;RESETS 5380
	mov AL,080H
	out DX,AL
	mov BL,0
@@:
	dec BL
	jne @B
	mov AL,00H
	out DX,AL
@@:
	dec BL
	jne @B
	RET

GETKEY: ;RETURNS KEY CODE IN AL, carry set if valid
	test SnapshotPending,0c0h	;if a snapshot is pending, disable
	jne @f			       ;the keyboard
	call ReadPCKey		       ;get code keyboard buffer
	jnc @f
	mov KeyCode,al
	stc
@@:
	ret				;return with carry set


	IF FORCEEXPORT
ExportBitmap:
	;set COM2 to 115.2 kbaud
	mov bx,6
	call BaudInBX

	;reset test byte counter
	mov ErrorEAX,0

	;transmit header
	mov si,offset BitmapHeader
	mov cl,54
@@:
	mov al,fs:[si]
	call SendSerialByte
	jc ExportError
	inc si
	dec cl
	jnz @b
	;transmit colour map
	mov dx,03dah		       ;reset index/value toggle
	in al,dx
	mov dx,03c0h
	mov al,34h		       ;index 14
	out dx,al
	inc dx
	in al,dx		       ;get colour select register
	dec dx
	and al,0ch
	shl al,4
	mov ColourSelect,al
	mov PaletteRegNo,0
@@:
	mov dx,03dah		       ;reset index/value toggle
	in al,dx
	mov al,PaletteRegNo
	mov dx,3c0h
	out dx,al
	inc dx
	in al,dx
	or al,ColourSelect	       ;colour reg number in al
	mov dx,3c7h
	out dx,al
	add dx,2

	in al,dx		      ;read red value
	shl al,2
	mov bh,al

	in al,dx		      ;read green value
	shl al,2
	mov bl,al

	in al,dx		      ;read blue value
	shl al,2
	call SendSerialByte	      ;send blue
	jc ExportError
	mov al,bl
	call SendSerialByte	      ;green
	jc ExportError
	mov al,bh
	call SendSerialByte	      ;red
	jc ExportError
	mov al,0
	call SendSerialByte	      ;null
	jc ExportError
	mov al,PaletteRegNo
	inc al
	mov PaletteRegNo,al
	cmp al,16
	jne @b

	mov dx,03dah		       ;reset index/value toggle
	in al,dx
	mov dx,3c0h
	mov al,20h
	out dx,al
	;transmit picture
	call ScrnAd
	add bx,38320
	mov ScreenAddress,bx
	mov ScanLine,0
SaveBM2:
	mov dx,03ceh
	mov al,04h
	out dx,al
	inc dx
	mov bh,80h
	mov si,ScreenAddress
	mov cx,80
SaveBM1:
	mov ah,0
	mov bl,3
@@:
	mov al,bl		       ;bl=read plane
	out dx,al
	mov al,es:[si]
	and al,bh
	setnz al
	shl ah,1
	or ah,al
	sub bl,1
	jnc @b
	mov bl,3
	ror bh,1
@@:
	mov al,bl		       ;bl=read plane
	out dx,al
	mov al,es:[si]
	and al,bh
	setnz al
	shl ah,1
	or ah,al
	sub bl,1
	jnc @b
	mov al,ah
	push dx
	call SendSerialByte
	pop dx
	jc ExportError
	ror bh,1
	jnc SaveBM1
	inc si
	loop SaveBM1
	sub ScreenAddress,80
	mov ax,ScanLine
	inc ax
	mov ScanLine,ax
	cmp ax,480
	jne SaveBM2
	ret

SendSerialByte:
	mov ah,al
	;sends a byte to com2
	mov edi,1000000
	mov dx,2feh
@@:				       ;wait for DSR and CTS to go high
	dec edi
	jz SendSByte1
	in al,dx
	and al,30h
	cmp al,30h
	jne @b

	mov edi,100000
	dec dx
@@:				       ;wait for transmitter to be empty
	dec edi
	jz SendSByte1
	in al,dx
	test al,20h
	je @b

	mov al,ah
	mov dx,2f8h
	out dx,al
	inc ErrorEAX
	clc
	ret

SendSByte1:
	stc
	ret

ExportError:
	mov BitmapError,1
	ret
	ENDIF

ReadPCKey:
	;this checks to see if there is a key in the buffer
	;carry is set if a key is down
	movzx bx,KeyBufTail
	cmp bl,KeyBufHead
	je @f
	mov al,KeyboardBuffer[bx]
	inc bl
	and bl,0fh
	mov KeyBufTail,bl
	stc
@@:
	ret			       ;return with code in al


ScanKeypad:
	;this scans membrane keypad and stores any keystrokes in the buffer
	mov bl,10h		       ;row counter
	mov dx,0211h		       ;keyboard port
	in al,dx		       ;read it
	test al,010h		       ;remote event mark?
	je @f			       ;if not,jump
	mov al,19h		       ;emulate event mark code
	jmp GetK6		       ;finish
@@:

	mov al,bl
	shl al,04
	or al,NOOFBITS		       ;02 for 7 bit, 06 for 8 bit
	or al,CoaxPower
	out dx,al		       ;output row number on upper 4 bits

	in  al,dx		       ;read keys in lower 4 bits
	mov bh,04		       ;4 keys per row
	shl al,4
GETK1:
	shl al,1
	jc  GETK3
	dec bh
	jnz getK1
	dec bl
	jnz @b
	mov al,0FFH		       ;no key down, return 0ffh
	jmp GetK6
GETK3:
	mov al,10H		       ;key code is 4*row number
	sub al,bl		       ;+column number
	shl al,02
	dec bh
	add al,bh		       ;in al

GetK6:
	cmp al,LastKeyCode	       ;any change?
	jne NewKeyDown
	cmp al,0ffh
	jne @f
	clc			       ;no new key
	ret
@@:
	inc AutoRepDel
	cmp AutoRepDel,8
	ja StoreKCode
	clc
	ret

NewKeyDown:
	;was key just pressed?
	cmp LastKeyCode,0ffh
	jne @f
	;key just pressed
	mov LastKeyCode,al
	;store code in buffer
StoreKCode:
	movzx bx,KeyBufHead
	mov KeyboardBuffer[bx],al
	inc bl
	and bl,0fh
	mov KeyBufHead,bl
	stc
	ret
@@:
	;key has just been released
	mov LastKeyCode,0ffh
	mov AutoRepDel,0
	clc
	ret


StoreRegs:
	mov ErrorEAX,eax
	mov ErrorEBX,ebx
	mov ErrorECX,ecx
	mov ErrorEDX,edx

	mov ErrorESI,esi
	mov ErrorEDI,edi

	mov ax,fs
	shl eax,16
	mov ax,gs
	mov ErrorFGS,eax
	ret

DebugInt:
	pushad
	;mov bp,sp
	;mov ax,'TD'
	;mov si,offset testmsg
	;mov [si],ax
	;add si,2
	;mov AL,05H		       ;SET WRITE MODE 2
	;mov AH,02H		       ;READ MODE 0
	;call SETGCR
	;mov al,DarkStatText
	;mov TextColour,al
	;mov bp,sp
	mov eax,ss:[bp+32]
	mov al,KeyBufHead
	mov ErrorEAX,eax

	;cmp ax,offset DebugLabel
	;je Debug2
	;mov cl,8
;Debug1:
	;rol eax,4
	;mov bl,al
	;and bl,0fh
	;add bl,30h
	;cmp bl,39h
	;jbe @f
	;add bl,7
;@@:
	;mov [si],bl
	;inc si
	;cmp cl,5
	;jne @f
	;mov byte ptr [si],':'
	;inc si
;@@:
	;dec cl
	;jnz Debug1
	;mov byte ptr [si],0ffh
	;mov si,offset testmsg
	;call scrnad
	;add bx,2618
	;call bgtext
Debug2:
	xor eax,eax
	mov dr6,eax
	popad
	iret



pint:	;protection error interrupt vector
	pop eax
	mov ErrorT1,eax
	call StoreRegs
	pop ax
	mov ax,'PG'
	jmp @f

dzint:	;divide fault
	call StoreRegs
	mov ax,'FD'
@@:

	cli
	mov si,offset testmsg
	mov [si],ax
	add si,2
	mov AL,05H		       ;SET WRITE MODE 2
	mov AH,02H		       ;READ MODE 0
	call SETGCR
	mov al,DarkStatText
	mov TextColour,al
	pop eax
	mov cl,8
prote1:
	rol eax,4
	mov bl,al
	and bl,0fh
	add bl,30h
	cmp bl,39h
	jbe @f
	add bl,7
@@:
	mov [si],bl
	inc si
	cmp cl,5
	jne @f
	mov byte ptr [si],':'
	inc si
@@:
	dec cl
	jnz prote1
	mov byte ptr [si],0ffh
	mov si,offset testmsg
	call scrnad
	add bx,2618
	call bgtext
	mov InitRedraw,0
	;mov al,REPINTMASK
	;out 21h,al
	sti
	byte 0EAH
	WORD offset KeyDone
	WORD 0008H



ExitToDos:
	;this returns to the dos prompt
	cmp StorageMode,02h		       ;in record mode?
	jne @f
	mov si,offset ErrorMsg10
	call Rebuke
	jmp KeyDone
@@:
	cmp StorageMode,01h		       ;in play mode?
	jne @f
	mov si,offset ErrorMsg8
	call Rebuke
	jmp KeyDone
@@:
	in al,61h		       ;turn off sound
	and al,0fch
	out 61h,al
	mov al,2		       ;turn off coax power
	mov dx,211h
	out dx,al
	xor eax,eax
	mov dr7,eax
	mov dr6,eax
	call SwitchToRealMode
	;unlock XMS block
	mov dx,XMSHandle
	mov ah,0dh
	call dword ptr HandlerOffset
	;de-allocate XMS
	mov dx,XMSHandle
	mov ah,0ah
	call dword ptr HandlerOffset
	mov ah,06h		       ;local disable A20
	call dword ptr HandlerOffset
	;now set the timer tick value at 40:6c to the correct value
	mov bp,BiosSeg		       ;set ds to bios data area
	mov ds,bp

	ASSUME DS:BiosSeg

@@:
	mov al,0ah		       ;if the real time clock is
	out 070h,al		       ;updating the time, bit 7 of
	in al,71h		       ;byte 0ah is set and the time
	test al,80h		       ;should not be read
	jne @b			       ;if so, jump back
	;now read time
	mov al,0
	out 70h,al
	in al,71h		       ;read seconds
	call BCDtoBinary
	mov bl,al
	mov al,2
	out 70h,al
	in al,71h		       ;read minutes
	call BCDtoBinary
	mov bh,al
	mov al,4
	out 70h,al
	in al,71h		       ;read hours
	call BCDtoBinary
	movzx dx,al
	shl edx,16		       ;TickCounter=
	mov al,bh		       ;(Seconds+60*Minutes+3600*Hours)*18.2
	mov ah,60
	mul ah
	mov bh,0
	add ax,bx		       ;ax holds seconds+60*minutes
	mov bx,91		       ;18.2=91/5
	mul bx
	mov bx,5
	div bx
	mov dx,ax
	mov TickCounter,edx	       ;store value in BIOS data area
	mov bp,dseg
	mov ds,bp


	ASSUME DS:DSEG
	;set video mode to 03h
	mov ax,03h
	int 10h

	cmp DriveError,1
	jne @f
	mov dx,offset NoDriveMsg
	mov ah,9
	int 21h
@@:
	mov ah,04ch		       ;back to dos prompt
	int 021h



SwitchToRealMode:
	;this switches the processor back to real mode
	;and sets the interrupt vectors back to DOS values
	;timer 0 is set to 18.2 per second
	;call by a near call
	cli			       ;mask interrupts
	mov al,0bh			;disable interrupts
	out 70h,al			;on RTC
	mov al,02h
	out 71h,al
	;now set interupt controllers back to DOS values
	mov al,11h		       ;ICW1
	out 020h,al
	out 0a0h,al

	mov al,08h		       ;ICW2 (vectors)
	out 021h,al
	mov al,70h
	out 0a1h,al

	mov al,04h		       ;ICW3
	out 021h,al
	mov al,02h
	out 0a1h,al

	mov al,01h		       ;ICW4
	out 021h,al
	out 0a1h,al

	mov al,MaskValue1	       ;Mask register
	out 021h,al
	mov al,MaskValue2
	out 0a1h,al
	;restore timer 0
	mov al,036h
	out 43h,al
	mov al,0
	out 40h,al
	out 40h,al
	;now load the IDTR with RM values ie start at 0
	;with a limit of 03ffh to be compatible with the
	;real mode interrupt structure
	mov bx,offset RMTABLE
	LIDT DescriptorTable PTR [BX]	       ;LOAD IDT REGISTER
	;now set data segments to RM compatible by setting the selectors
	;to the printer buffer segment which is a read/write segment
	;with a limit off 0ffffh
	mov bp,030h
	mov fs,bp
	mov gs,bp
	mov es,bp
	mov ds,bp
	mov ss,bp
	mov eax,0
	mov cr0,eax
	jmp FAR PTR @f			       ;jump to real mode
@@:
	mov bp,DSEG
	mov ds,bp
	mov bp,SSEG
	mov ss,bp
	sti
	ret

SwitchToProtMode:
	;this switches the processor into protected mode
	;call by a near call
	ASSUME DS:DSEG
	cli
	mov bp,DSEG
	mov ds,bp
	;save old interrupt mask values
	in al,021h
	mov MaskValue1,al
	in al,0a1h
	mov MaskValue2,al
	;set up the interrupt controllers for protected
	;mode operation ie. avoid vectors reserved for processor use
	mov al,11h		       ;ICW1
	out 020h,al
	out 0a0h,al

	mov al,020h		       ;ICW2 (vectors)
	out 021h,al
	mov al,28h
	out 0a1h,al

	mov al,04h		       ;ICW3
	out 021h,al
	mov al,02h
	out 0a1h,al

	mov al,01h		       ;ICW4
	out 021h,al
	out 0a1h,al

	mov al,0ffh		       ;Mask register
	out 021h,al
	mov al,0eeh
	out 0a1h,al

	call SetupRTC

	;now load descriptor table registers
	mov bx,offset dtable
	lgdt DescriptorTable ptr [bx]	       ;LOAD GDT REGISTER
	mov bx,offset itable
	lidt DescriptorTable ptr [bx]	       ;LOAD IDT REGISTER
	mov eax,01h
	mov cr0,eax		       ;PREPARE TO SWITCH TO PROTECTED MODE

	byte 0eah		       ;JUMP TO PROTECTED MODE
	word offset ProtectedMode	;HAS TO
	word 0008h		       ;BE DONE WITH BYTE/WORD (0EAH=JMP)
ProtectedMode:
	;now load segment registers with protected mode selectors
	mov bp,010h
	mov ds,bp		       ;ds is dynamic data
	mov bp,018h
	mov ss,bp		       ;ss is stack
	mov bp,020h
	mov es,bp		       ;es is video
	mov bp,028h
	mov fs,bp		       ;fs is static data

	IF DOS			       ;interrupts
	mov AL,DOSINTMASK	       ;UART(5) MOUSE(4) keyboard(1)  nav(3)
	ELSE			       ;cascade(2)
	mov al,REPINTMASK	       ;mouse (4) keyboard (1)
	ENDIF
	out 021h,al
	sti
	ret

	IFE FORCEEXPORT
SaveBitmap:
	;fill in the colour map
	mov dx,03dah
	in al,dx
	mov dx,03c0h
	mov al,34h
	out dx,al
	inc dx
	in al,dx		       ;get colour select register
	and al,0ch
	shl al,4
	mov al,0
	mov ColourSelect,al
	;now read each palette register and get its true
	;colour from the colour registers and load this into
	;the ColourMap
	mov PaletteRegNo,0
@@:
	mov bl,PaletteRegNo
	mov ax,1007h		       ;read palette register bl
	int 10h			       ;colour code in bh
	mov bl,bh
	mov bh,0
	or bl,ColourSelect
	mov ax,1015h		       ;read colour register bx
	int 10h		       ;ch=green, cl=blue, dh=red
	shl cx,2
	shl dh,2
	movzx di,PaletteRegNo
	shl di,2
	add di,offset ColourMap
	mov [di],cx		       ;store the RGB values in the
	mov [di+2],dh		       ;ColourMap
	mov al,PaletteRegNo
	inc al
	mov PaletteRegNo,al
	cmp al,16
	jne @b
	;now open a new file
	mov ah,03ch
	xor cx,cx
	mov dx,offset FileName
	int 21h
	jnc @f
	mov BitmapError,1
	ret
@@:
	mov FileHandle,ax
	;write the header and colour map to the file
	mov bx,ax
	mov ah,40h
	mov cx,118
	mov dx,offset BitmapHeader
	int 21h
	;
	call ScrnAd
	add bx,38320
	mov ScreenAddress,bx
	mov ScanLine,0
SaveBM2:
	mov dx,03ceh
	mov al,04h
	out dx,al
	inc dx
	mov bp,0a000h
	mov es,bp
	mov si,offset LineBuffer
	mov bh,80h
	mov di,ScreenAddress
	mov cx,80
SaveBM1:
	mov ah,0
	mov bl,3
@@:
	mov al,bl		       ;bl=read plane
	out dx,al
	mov al,es:[di]
	and al,bh
	setnz al
	shl ah,1
	or ah,al
	sub bl,1
	jnc @b
	mov bl,3
	ror bh,1
@@:
	mov al,bl		       ;bl=read plane
	out dx,al
	mov al,es:[di]
	and al,bh
	setnz al
	shl ah,1
	or ah,al
	sub bl,1
	jnc @b
	mov [si],ah
	inc si
	ror bh,1
	jnc SaveBM1
	inc di
	loop SaveBM1
	mov bx,FileHandle
	mov ah,40h
	mov cx,320
	mov dx,offset LineBuffer
	int 21h
	sub ScreenAddress,80
	mov ax,ScanLine
	inc ax
	mov ScanLine,ax
	cmp ax,480
	jne SaveBM2
	mov ah,3eh		       ;close the file
	mov bx,FileHandle
	int 21h
	ret
	ENDIF

BCDtoBinary:
	;converts a packed BCD value in al to a binary value in al
	mov ah,al
	and al,0fh
	and ah,0f0h
	shr ah,1
	add al,ah
	shr ah,2
	add al,ah
	ret



CSFIN:	;END OF CODE SEGMENT

CSEG	ENDS


FSEG	SEGMENT USE16
FSBEG:	;START OF STATIC DATA

CMAXLogo    byte 0,0,0,0,000h,07fh,000h,000h,0feh,007h,0f0h,00fh,0c0h,03fh,003h,0f0h
	    byte 0,0,0,0,001h,0ffh,080h,000h,0feh,007h,0f0h,00fh,0c0h,01fh,083h,0f0h
	    byte 0,0,0,0,003h,0ffh,0c0h,000h,0feh,007h,0f0h,01fh,0c0h,01fh,087h,0e0h
	    byte 0,0,0,0,007h,0ffh,0e0h,000h,0feh,00fh,0f0h,01fh,0e0h,00fh,0cfh,0c0h
	    byte 0,0,0,0,00fh,0ffh,0e0h,001h,0feh,00fh,0f0h,03fh,0e0h,00fh,0dfh,080h
	    byte 0,0,0,0,01fh,0c3h,0f0h,001h,0feh,01fh,0f0h,03fh,0e0h,007h,0ffh,000h
	    byte 0,0,0,0,03fh,083h,0f0h,001h,0feh,01fh,0e0h,03fh,0e0h,007h,0feh,000h
	    byte 0,0,0,0,03fh,003h,0f0h,001h,0ffh,03fh,0e0h,07dh,0e0h,007h,0fch,000h
	    byte 0,0,0,0,03fh,000h,000h,001h,0ffh,03fh,0e0h,079h,0f0h,003h,0f8h,000h
	    byte 0,0,0,0,07eh,000h,000h,001h,0efh,03fh,0e0h,0f9h,0f0h,003h,0f8h,000h
	    byte 0,0,0,0,07eh,000h,003h,0f3h,0efh,07bh,0e0h,0f9h,0f0h,003h,0f8h,000h
	    byte 0,0,0,0,07eh,000h,003h,0f3h,0efh,07bh,0e1h,0f1h,0f0h,007h,0f8h,000h
	    byte 0,0,0,0,07eh,000h,007h,0f3h,0efh,0f3h,0c1h,0f0h,0f0h,007h,0fch,000h
	    byte 0,0,0,0,07eh,003h,0e7h,0e3h,0efh,0f3h,0c3h,0ffh,0f8h,00fh,0fch,000h
	    byte 0,0,0,0,07eh,007h,0e7h,0e3h,0c7h,0f7h,0c3h,0ffh,0f8h,01fh,0feh,000h
	    byte 0,0,0,0,07fh,00fh,0c0h,003h,0c7h,0e7h,0c7h,0ffh,0f8h,03fh,07eh,000h
	    byte 0,0,0,0,03fh,0ffh,080h,007h,0c7h,0e7h,0c7h,0ffh,0f8h,03eh,03eh,000h
	    byte 0,0,0,0,01fh,0ffh,000h,007h,0c7h,0c7h,0cfh,0c1h,0f8h,07eh,03fh,000h
	    byte 0,0,0,0,01fh,0ffh,000h,007h,0c7h,0c7h,08fh,080h,0fch,0fch,03fh,000h
	    byte 0,0,0,0,007h,0fch,000h,007h,0c7h,08fh,09fh,080h,0fdh,0f8h,03fh,080h
	    byte 16*8 dup (0)



StatusMsgTable	word 167
		word offset LaybackMsg
		word 161
		word offset Spedmsg
		word 2161
		word offset HeadingMsg
		word 2167
		word offset AngleMsg

		word 174
		word offset ScopeMsg
		word 2174
		word offset SoundingMsg

		word 182
		word offset ZoomMsg
		word 2182
		word offset Geommsg

		word 192
		word offset FishMsg
		word 2197
		word offset RngLMsg
		word 232
		word offset TimeMsg
		word 2232
		word offset PrnMdMsg

	IFE REPLAY
		word 197
		word offset BattMsg
	ENDIF

		word 2192
		word offset AltiMsg
		word 203
		word offset RecMsg
		word 2203
		word offset ModeMsg
		word 2209
		word offset SpaceMsg
		word 0
		word 0ffffh

RegisterTable	word 'XA'
		word 'XB'
		word 'XC'
		word 'XD'
		word 'IS'
		word 'ID'
		word 'GF'
		word '1T'
		word '2T'

DitherPattern	word 0000000000000000b	    ;0
		word 0000010000000000b	    ;1
		word 0010000010000000b	    ;2
		word 1000001001000000b	    ;3
		word 1010000010100000b	    ;4
		word 1010000110000100b	    ;5
		word 0101100000011010b	    ;6
		word 0101001001011010b	    ;7

		word 1010010110100101b	    ;8
		word 1010110110100101b	    ;9
		word 1010011111100101b	    ;10
		word 0101111001111011b	    ;11
		word 0101111101011111b	    ;12
		word 0111110110111111b	    ;13
		word 1101111101111111b	    ;14
		word 1111111111111111b	    ;15

	    IF 1
PrinterColours	byte 09,07,05,04,03,02,01,00,00,00,00,00,00,00,00,00
		byte 08,08,07,06,05,05,04,04,03,03,02,02,01,01,00,00
		byte 07,07,07,07,07,07,07,07,07,07,07,07,07,07,07,07
	    ENDIF

	    IF 0
PrinterColours	byte 00,01,02,03,04,05,00,00,00,00,00,00,00,00,00,00
		byte 00,00,00,00,00,00,01,02,03,04,05,00,00,00,00,00
		byte 00,00,00,00,00,00,00,00,00,00,00,01,02,03,04,05

	    ENDIF














PrntModeMsg byte 'Off     __',0ffh
	    byte 'Full width',0ffh
	    byte 'Port side_',0ffh
	    byte 'Stbd side_',0ffh

testModeMsg byte 'test   ___',0ffh

PrntTypeMsg byte 'None     ',0ffh
	    byte 'DeskJet  ',0ffh
	    byte 'TDU850   ',0ffh
	    byte '         ',0ffh
	    byte '9315CTP  ',0ffh
	    byte 'Ultra`200',0ffh
	    byte '3710     ',0ffh
	    byte 'GSP1086  ',0ffh
	    byte 'EPC9800  ',0ffh
	    byte 'GP608P   ',0ffh

fishmsg byte 'Freq.',0ffh
typemsg	byte 'HF',0ffh
	byte 'LF',0ffh
	byte '||',0ffh
BlankType   byte '||',0ffh
rnglmsg byte 'Range',0ffh
geommsg byte 'Geometry',0ffh
spedmsg byte 'Speed',0ffh
timemsg byte 'Time',0ffh
DateMsg byte 'Date',0ffh
altimsg byte 'Altitude',0ffh
SpaceMsg byte 'Disk Space',0ffh
battmsg byte 'Battery',0ffh
zoommsg byte 'Zoom + Pan',0ffh
LaybackMsg  byte 'Layback',0ffh
ScopeMsg    byte 'Scope',0ffh
SoundingMsg byte 'Sounding',0ffh
AngleMsg    byte 'Crab Ang.',0ffh
HeadingMsg  byte 'Course',0ffh
PrntrMsg    byte 'Printer',0ffh
PrnMdMsg    byte 'Print Mode',0ffh
RecMsg	byte 'Current Record',0ffh
ModeMsg byte 'Mode',0ffh

TransDigit  byte '0123456789,.$GPL'
OldToNew    byte 00h,30h,48h,68h,80h,90h,0a8h,0b8h,0c8h,0d0h,0dch,0e4h,0ech,0f4h,0f8h,0ffh

AlarmTones  byte 0
	    byte 11001100b		;fish stopped
	    byte 10101010b		;low altitude
	    byte 11110000b		;low disk
	    byte 10101000b		;leak (not used)
	    byte 10100000b		;lag
	    byte 0,0,0

	;function menu text

FuncMenuText	byte 0e0h,'FUNCTION MENU',0efh,0ffh
	byte 0ffh
	IF REPLAY
	byte 0c3h,' event marks',0b4h,0e0h,'V',0e9h,0b8h,'St',0cfh,' towfish (coax)',0bch,0e0h,'F',0efh,0ffh
	byte 0c1h,' altitude indication',0b4h,0e0h,'B',0e9h,0b8h,'Range out (coax)',0bch,0e0h,'O',0efh,0ffh
	byte 0c0h,' annotation',0b4h,0e0h,'A',0e9h,0b8h,'Range in (coax)',0bch,0e0h,'I',0efh,0ffh
	byte 0c6h,' range lines',0b4h,0e0h,'J',0efh,0ffh
	byte 0b8h,'Altitude modify',0bch,0e0h,'G',0efh,0ffh
	byte 'Set year',0b4h,0e0h,'Y',0e9h,0b8h,0cdh,'able altitude alarm',0bch,0e0h,'L',0efh,0ffh
	ELSE
	byte 0c3h,' event marks',0b4h,0e0h,'V',0efh,0b8h,'St',0cfh,' towfish (coax)',0bch,0e0h,'F',0efh,0ffh
	byte 0c1h,' altitude indication',0b4h,0e0h,'B',0efh,0b8h,'Range out (coax)',0bch,0e0h,'O',0efh,0ffh
	byte 0c0h,' annotation',0b4h,0e0h,'A',0efh,0b8h,'Range in (coax)',0bch,0e0h,'I',0efh,0ffh
	byte 0c6h,' range lines',0b4h,0e0h,'J',0efh,0ffh
	byte 0b8h,'Altitude modify o',0ceh,0bch,0e0h,'G',0efh,0ffh
	byte 'Set year',0b4h,0e0h,'Y',0efh,0b8h,0cdh,'able altitude alarm',0bch,0e0h,'L',0efh,0ffh
	ENDIF
	byte 'Set month',0b4h,0e0h,'M',0efh,0ffh
	byte 'Set day',0b4h,0e0h,'D',0efh,0b8h,'Set event number',0bch,0e0h,'N',0efh,0ffh
	byte 'Set hour',0b4h,0e0h,'H',0efh,0b8h,'Set replay sequence',0bch,0e0h,'S',0efh,0ffh
	byte 'Set minute',0b4h,0e0h,'T',0efh,0b8h,'Set replay repeat',0bch,0e0h,'R',0efh,0ffh
	byte 0ffh
	byte 'Erase disk',0b4h,0e0h,'ZZZ',0efh,0b8h,'Change palette',0bch,0e0h,'P',0efh,0ffh
	byte 'Erase last record',0b4h,0e0h,'UUU',0efh,0b8h,'Set mouse speed (1-5)',0bch,0e0h,'C',0efh,0ffh
	byte 'Eject disk',0b4h,0e0h,'E',0efh,0ffh
	IF FORCEEXPORT
	byte 'Rename disk',0b4h,0e0h,'X',0efh,0b8h,'Export Windows bitmap',0bch,0e0h,'W',0efh,0ffh
	ELSE
	byte 'Rename disk',0b4h,0e0h,'X',0efh,0b8h,'Save as Windows bitmap',0bch,0e0h,'W',0efh,0ffh
	ENDIF
	byte 0ffh
	byte 'Before ',0e0h,'Y',0efh,', ',0e0h,'M',0efh,', ',0e0h,'D',0efh,', ',0e0h,'H',0efh
	byte ' or ',0e0h,'T',0efh,' enter a 2-digit number',0ffh
	byte 'Before ',0e0h,'N',0efh,' ,',0e0h,'S',0efh,' or ',0e0h,'R',0efh,' enter a 4-digit number',0ffh
	byte 0ffh
	byte 'Enter a name before selecting ',0e0h,'FUNC MENU ',0efh,'-',0e0h,' X',0efh,' or ',0e0h,'FUNC MENU ',0efh,'-',0e0h,' W',0efh,0ffh
	byte 0ffh
	byte 'Press ',0e0h,'Q',0efh,' to cancel',0ffh
	byte 0feh

StatPageText	byte 0e0h,'SYSTEM STATUS',0efh,0ffh
	byte 0ffh
	byte 'MISC. VALUES',0ffh
	byte 0ffh
	byte 'Buffer size:',0ffh
	byte 'Ping size:',0ffh
	byte 0ffh
	byte 0ffh
	byte 'TOWFISH POWER',0ffh
	byte 0ffh
	byte 'Coax board type:',0ffh
	byte 'Coax power status:',0ffh
	byte 'Coax drive voltage:',0ffh
	byte 'Regulator input:',0ffh
	byte 'Regulator output:',0ffh
	byte 'Battery voltage:',0ffh
	byte 0ffh
	byte 0ffh
	byte 0ffh
	byte 0ffh
	byte 0ffh
	byte 0ffh
	byte 0ffh
	byte 'Press ',0e0h,'Q',0efh,' to cancel',0ffh
	byte 0feh


	;printer menu text

PrintMenuText	byte 0e0h,'PRINTER MENU',0efh,0ffh
	byte 0ffh
	byte 'Print format:',0b8h,'Printer type:',0ffh
	byte 0ffh
	byte 'Continuous print all',0b4h,0e0h,'A',0efh,0b8h,'None connected',0bch,0e0h,'0',0efh,0ffh
	byte 'Continuous print port',0b4h,0e0h,'P',0efh,0ffh
	byte 'Continuous print stbd',0b4h,0e0h,'S',0efh,0b8h,'HP DeskJet/LaserJet',0bch,0e0h,'1',0efh,0ffh
	byte 0ffh
	byte 'Printer off',0b4h,0e0h,'O',0efh,0b8h,'Raytheon',0bah,'TDU-850',0bch,0e0h,'2',0efh,0ffh
	byte 0e9h,0bah,'TDU-1200',0bch,0e0h,'3',0efh,0ffh
	byte 0ffh
	byte 0b8h,'Alden',0bah,'9315CTP',0bch,0e0h,'4',0efh,0ffh
	byte 'Test printer',0b4h,0e0h,'T',0efh,0ffh
	byte 0b8h,'Ultra',0bah,'200',0bch,0e0h,'5',0efh,0ffh
	byte 'Screen snapshot all',0b4h,0e0h,'D',0efh,0bah,'3710',0bch,0e0h,'6',0efh,0ffh
	byte 'Screen snapshot port',0b4h,0e0h,'L',0efh,0ffh
	byte 'Screen snapshot stbd',0b4h,0e0h,'R',0efh,0b8h,'EPC',0bah,0efh,'GSP1086',0bch,0e0h,'7',0efh,0ffh
	byte 0bah,'9800',0bch,0e0h,'8',0efh,0ffh
	byte 0ffh
	byte 'Snapshots allowed in Play mode only',0ffh
	byte 0ffh
	byte 'For setup and operation of individual printers, see CM800 and printer handbooks',0ffh
	byte 0ffh
	byte 'Press ',0e0h,'Q',0efh,' to cancel',0ffh
	byte 0feh

NavMenuText byte 0e0h,'NAVIGATION DATA MENU',0efh,0ffh
	byte 0ffh
	byte 'Baud rate:',0b8h,'Set speed',0bch,0e0h,'S',0efh,0ffh
	byte 0b8h,'Set course',0bch,0e0h,'G',0efh,0ffh
	byte 0e0h,0d1h,0efh,'1200',0b4h,0e0h,'V',0efh,0ffh
	byte 0e0h,0d2h,0efh,'2400',0b4h,0e0h,'W',0efh,0b8h,'Set relative heading:',0ffh
	byte 0e0h,0d3h,0efh,'4800',0b4h,0e0h,'X',0efh,0b8h,' if positive (+45* max)',0bch,0e0h,'P',0efh,0ffh
	byte 0e0h,0d4h,0efh,'9600',0b4h,0e0h,'Y',0efh,0b8h,' if negative (+45* max)',0bch,0e0h,'N',0efh,0ffh
	byte 0e0h,0d5h,0efh,'19200',0b4h,0e0h,'Z',0efh,0ffh
	byte 0b8h,'Speed in knots',0bch,0e0h,'K',0efh,0ffh
	byte 0e0h,0d8h,0efh,'Hide nav data',0b4h,0e0h,'D',0efh,0b8h,'Speed in m/s',0bch,0e0h,'M',0efh,0ffh
	byte 0e0h,0d9h,0efh,'Show position only',0b4h,0e0h,'E',0efh,0ffh
	byte 0e0h,0ddh,0efh,'Show all nav data',0b4h,0e0h,'F',0efh,0ffh
	IF DOS
	byte 0b8h,'Reset scope',0bch,0e0h,'R',0efh,0ffh
	ELSE
	byte 0ffh
	ENDIF
	byte 0ffh
	byte 'NMEA0183B/D:',0ffh
	byte 'Lat/Long (GLL), Course/Speed (VTG), Heading (HDT), Time (UTC), Sounding (DBS/DBT)',0ffh
	byte 0ffh
	byte 'Eastings/Northings:',0ffh
	byte 'X (+/- metres), Y (+/- metres) or E (+/- metres), N (+/- metres)',0ffh
	byte 0ffh
	byte 'Last position fix:',0ffh
	byte 0ffh
	byte 'Press ',0e0h,'Q',0efh,' to cancel',0ffh
	byte 0feh

HPConfigMsg byte 'SURVEYED:          RANGE:       FREQUENCY:     C-MAX CM800 SONAR'

BitmapWriteMsg	byte 'Writing',0ffh
BitmapExprtMsg	byte 'Exporting',0ffh
WaitingMsg	byte 'Starting..',0ffh
ChangingMsg	byte 'Changing..',0ffh

ErrorMsg1   byte '10 chars only',0ffh
ErrorMsg2   byte 'Wrt protected',0ffh
ErrorMsg3   byte 'Invalid key',0ffh
ErrorMsg4   byte 'Zoom limit',0ffh
ErrorMsg5   byte 'Pan limit',0ffh
ErrorMsg6   byte 'Wrong record',0ffh
ErrorMsg7   byte 'No disk',0ffh
ErrorMsg8   byte 'In play mode',0ffh
ErrorMsg9   byte 'Disk full',0ffh
ErrorMsg10  byte 'In record mode',0ffh
ErrorMsg11  byte 'Invalid record',0ffh
ErrorMsg12  byte 'Invalid number',0ffh
ErrorMsg13  byte 'Invalid time',0ffh
ErrorMsg14  byte 'In cue mode',0ffh
ErrorMsg15  byte 'Wrong mode',0ffh
ErrorMsg16  byte 'Disk error',0ffh
ErrorMsg17  byte 'No text',0ffh
ErrorMsg18  byte 'Invalid angle',0ffh
ErrorMsg19  byte 'Noisy link',0ffh
ErrorMsg20  byte 'Refer C-MAX',0ffh
ErrorMsg21  byte 'Invalid speed',0ffh
ErrorMsg22  byte 'No nav data',0ffh
ErrorMsg23  byte 'Invalid course',0ffh
ErrorMsg24  byte 'No records',0ffh
ErrorMsg25  byte 'No printer',0ffh
ErrorMsg26  byte 'No nav fix',0ffh
ErrorMsg27  byte 'Aborted',0ffh
ErrorMsg28  byte 'Invalid string',0ffh
ErrorMsg29  byte 'Error test',0ffh
ErrorMsg30  byte 'Bad filename',0ffh
ErrorMsg31  byte 'Comms error',0ffh
ErrorMsg32  byte 'No response',0ffh
ErrorMsg33  byte 'No vector',0ffh
ErrorMsg34  byte 'Print conflict',0ffh
ErrorMsg35  byte 'Buffer full',0ffh
ErrorMsg36  byte 'No pulley',0ffh
ErrorMsg37  byte 'Not coax?',0ffh
ErrorMsg38  byte 'Range limit',0ffh
ErrorMsg39  byte 'Min range',0ffh
ErrorMsg40  byte 'No response',0ffh
ErrorMsg41  byte 'Erase disk',0ffh
ErrorMsg42  byte 'No update',0ffh
ErrorMsg43  byte 'Too high',0ffh
GeoMessage  byte 'Geometry?',0ffh
NewRangeMsg byte 'New range',0ffh
DumpDoneMsg byte 'Completed',0ffh
DemoMsg byte 'DEMO ONLY',0FFH
KeytestMsg  byte 'Key test on',0ffh
DrvErrorMsg byte 'Drive fault',0ffh

AlarmMsg1   byte 'Fish stopped',0ffh
AlarmMsg2   byte 'Low altitude',0ffh
AlarmMsg2a  byte 'No altitude',0ffh
AlarmMsg3   byte 'Low disk',0ffh
AlarmMsg4   byte 'Leak detected',0ffh
AlarmMsg5   byte 'Printer lagging',0ffh
QToCancelMsg	byte 'Q to cancel',0ffh

PrinterTypeMsg	byte 'Printer type:',0ffh

	IF (PSEA+DOS) EQ 2
BannerMessage	byte 'CM800 Software P-Sea Master Version ',VersionString,' Copyright C-MAX Ltd 1998',0ffh
	ELSEIF DOS
BannerMessage	byte 'CM800 Software DOS Version ',VersionString,' Copyright C-MAX Ltd 1998',0ffh
	ELSEIF REPLAY
BannerMessage	byte 'CM800 PC Replay Software Version ',VersionString,' Copyright C-MAX Ltd 1998',0ffh
	ELSE
BannerMessage	byte 'CM800 Demo Software Version ',VersionString,' Copyright C-MAX Ltd 1998',0ffh
	ENDIF

PrintDrivers	word offset SendPrintNull	;0=no printer
		word 12000

		word offset SendPrintLine1	;1=HP DeskJets
		word 12054

		word offset SendPrintLine2	;2=raytheon tdu 850
		word 9230

		word offset SendPrintNull	;3=(tdu-1200)
		word 9230

		word offset SendPrintLine4	;4=Alden 9315
		word 12000

		word offset SendPrintLine5	;5=dowty 200
		word 21717

		word offset SendPrintLine6	;6=Ultra 3710
		word 12000

		word offset SendPrintLine4	;7=EPC GSP1086
		word 12000

		word offset SendPrintLine8	;8=EPC 9800
		word 10858

		word offset SendPrintLine9	;9=Oyo GP608P
		word 9230

HPMessage1  byte 6,ESC,'*b64W'			;64 mono bytes
HPMessage5  byte 7,ESC,'*b512W' 		;512 mono bytes
HPMessage2  byte 7,ESC,'*b256V' 		;256 colour bytes
HPMessage3  byte 7,ESC,'*b256W' 		;256 mono bytes
HPMessage4  byte 12
	    byte ESC,'E'		;reset printer	      (12 bytes)
	    byte ESC,'&l0O'		;portrait mode
	    byte ESC,'&l0L'		;skip perf off

HPMessage6  byte 9
	    byte 0ch
	    byte ESC,'*p-300Y'


HPTextCodes byte 61			;(61 bytes)
	    byte ESC,'E'		;reset
	    byte ESC,'&l0O'		;portrait mode
	    byte ESC,'&l0L'		;skip perf off
	    byte ESC,'*rbC'		;end raster graphics
	    byte ESC,'*r1U'		;one plane
	    byte ESC,'*t75R'		;75 dpi
	    byte ESC,'*r512S'		;graphics width (pixels)
	    byte ESC,'*p0N'		;print mode
	    byte ESC,'*r1Q'		;draft quality
	    byte ESC,'*r0A'		;start graphics, leftmost position
	    byte ESC,'*b35Y'		;down 35 pixels (35/75 inch)
	    byte ESC,'*b0M'		;no compression

HPColorCodes byte 42
	    byte ESC,'*rbC'		;end raster graphics
	    byte ESC,'*r-3U'		;three planes, RGB
	    byte ESC,'*t300R'		;300 dpi
	    byte ESC,'*r2048S'		;graphics width (pixels)
	    byte ESC,'*r0A'		;start graphics, leftmost position
	    byte ESC,'*b30Y'		;down 30 pixels (1/10 inch)
	    byte ESC,'*b0M'		;no compression

HPMono300Codes byte 46
	    byte ESC,'*rbC'		;end raster graphics
	    byte ESC,'*r1U'		;one plane
	    byte ESC,'*t300R'		;300 dpi
	    byte ESC,'*r2Q'		;high quality
	    byte ESC,'*r2048S'		;graphics width (pixels)
	    byte ESC,'*r0A'		;start graphics, leftmost position
	    byte ESC,'*b30Y'		;down 30 pixels (1/10 inch)
	    byte ESC,'*b0M'		;no compression

HPMono600Codes byte 46
	    byte ESC,'*rbC'		;end raster graphics
	    byte ESC,'*r1U'		;one plane
	    byte ESC,'*t600R'		;300 dpi
	    byte ESC,'*r2Q'		;high quality
	    byte ESC,'*r2048S'		;graphics width (pixels)
	    byte ESC,'*r0A'		;start graphics, leftmost position
	    byte ESC,'*b30Y'		;down 30 pixels (1/10 inch)
	    byte ESC,'*b0M'		;no compression

HPBannerCodes byte 66
	    byte ESC,'E'		;reset
	    byte ESC,'&l-1H'		;continuous paper
	    byte ESC,'&l2A'		;US letter
	    byte ESC,'&l0L'		;skip perf off
	    byte ESC,'*rbC'		;end raster graphics
	    byte ESC,'*r1U'		;one plane
	    byte ESC,'*t300R'		;300 dpi
	    byte ESC,'*r2Q'		;high quality
	    byte ESC,'*r2048S'		;graphics width (pixels)
	    byte ESC,'*r0A'		;start graphics, leftmost position
	    byte ESC,'*b0M'		;no compression
	    byte ESC,'*p-300Y'


HPEjectCodes	byte 7
		byte ESC,'*rbC'		;end raster graphics
		byte ESC,'E'		;reset printer

Graph0Message	byte 6,13,'GRAP0'	;full width print (4096 pixels)
EPCMessage  byte 16,'C',10,0,'DataMode:',41h,'D',00h,10h
OyoCommand  byte 17,01bh,02ah,072h,036h,061h
	    byte 01bh,02ah,072h,'832',73h
	    byte 01bh,02ah,062h,031h,057h

AldenCommand	byte 128
		byte 01h		;start of header
		byte 0,0		;left margin (0)
		byte 8,0		;bytes per line (2048)
		byte 0,0		;image length (0=continuous)
		byte 0			;margin colour (white)
		byte 0			;line repeat (none)
		byte 0			;vertical compresion (0)
		byte 0			;pixel repeat (0)
		byte 1			;linear translation
		byte 0			;256 grey scale
		byte 0,0,0,0		;no image number
		byte 0			;no line spacing
		byte 30			;30 LPS
		byte 0			;paper type thru control panel
		byte 0,0		;no feed
		byte 10 dup (0) 	;reserved
		byte 'SELECT PAPER TYPE FROM * GROUP F'	;header message
		byte 'or ONLINE PRINT; NON * For BEST '
		byte 'OFFLINE; SET HEAD CALIB. OFF    '


HPGamma	    byte 0,0,0,4,4,4,1,1,5,5,2,2,6,6,3,7

NMEA1  byte '$GPGLL,5206.45,N,00225.16,W',0FFH
NMEA2  byte '$GPGLL,5206.45,N,00224.16,W',0FFH
NMEA3  byte '$GPGLL,5205.45,N,00223.16,W',0FFH
NMEA4  byte '$GPGLL,5204.45,N,00223.16,W',0FFH
;NMEA1	byte '$ X+000200 Y+000200',0FFH
;NMEA2	byte '$ X+000100 Y+000200',0FFH
;NMEA3	byte '$ E  000100  N  000100',0FFH
;NMEA4	byte '$ E  000000  N  000000',0FFH

ThisFar1    byte 'This far 1',0ffh
ThisFar2    byte 'This far 2',0ffh
ThisFar3    byte 'This far 3',0ffh
ThisFar4    byte 'This far 4',0ffh

HelpPage1   byte 0e0h,'INFORMATION',0bdh,'page 1',0ffh
	    byte 0ffh
	    byte 'Contents',0efh,0ffh
	    byte 0ffh
	    byte 'Status bar',0ffh
	    byte 'Keyboard',0ffh
	    byte 'Mouse',0ffh
	    byte 0ffh
	    byte 0e0h,'STATUS BAR',0efh,0ffh
	    byte 0ffh
	    byte 'Speed: speed-over-ground (kts or m/s) set locally, or remotely via the nav data',0ffh
	    byte 'interface, to give the correct aspect ratio when Map geometry is selected.',0ffh
	    byte 0ffh
	    byte 'Layback: horizontal distance between the ship and towfish.',0ffh
	    byte 0ffh
	    byte 'Course: actual track, normally set remotely via nav data interface.',0ffh
	    byte 0ffh
	    byte 'Crab Angle: difference between ship"s heading and actual track.',0ffh
	    byte 0ffh
	    byte 'Zoom + pan: current zoom and pan settings.',0ffh
	    byte 0ffh
	    byte 'Geometry: Map removes the central "water column" and corrects the aspect ratio',0ffh
	    byte 'in both directions. SRC provides only "slant range correction", ie across-track.',0ffh
	    byte 0ffh
	    byte 'Press ',0e0h,'Q',0efh,' to cancel, or ',0e0h,'INFO',0efh,' for more',0ffh
	    byte 0feh

HelpPage2   byte 0e0h,'STATUS BAR (continued)',0bdh,'page 2',0efh,0ffh
	    byte 0ffh
	    byte 'Palette: shows current palette (greyscale or colour).',0ffh
	    byte 0ffh
	    byte 'Freq: either HF or LF type towfish connected.',0ffh
	    byte 0ffh

	    IFE REPLAY
	    byte 'Battery: the normal operating range is 7.5v to 5.8v.',0ffh
	    byte 0ffh
	    ENDIF

	    byte 'Range: towfish range, eg 100m range = 200m total width.',0ffh
	    byte 0ffh
	    byte 'Altitude: indicated towfish altitude always lies between 2.2 and 20m (HF) or 2.5',0ffh
	    byte 'and 40m (LF). 3m or less sounds an alarm.',0ffh
	    byte 0ffh
	    byte 'Mode: Record/replay mode (Live indicates display is direct from the towfish but is not',0ffh
	    byte 'being recorded).',0ffh
	    byte 0ffh
	    byte 'Disk Space: free capacity of the optical disk. 3% or less sounds an alarm.',0ffh
	    byte 0ffh
	    byte 'Annotation box: used to enter annotation text, record titles and function parameters.',0ffh
	    byte 0ffh
	    byte 'Message box: displays error messages, prompts and measurements.',0ffh
	    byte 0ffh
	    byte 'Printer: selected greyscale printer.',0ffh
	    byte 0ffh

	    IF REPLAY
	    byte 0ffh,0ffh
	    ENDIF

	    byte 'Press ',0e0h,'Q',0efh,' to cancel, or ',0e0h,'INFO',0efh,' for more',0ffh
	    byte 0feh

HelpPage3   byte 0e0h,'STATUS BAR (continued)',0bdh,'page 3',0efh,0ffh
	    byte 0ffh
	    byte 'Print Mode: current status of the greyscale printer.',0ffh
	    byte 0ffh
	    byte 'Time and Date: used during recording.',0ffh
	    byte 0ffh
	    byte 0ffh
	    byte 0e0h,'KEYBOARD',0efh,0ffh
	    byte 0ffh

	    IF REPLAY
	    byte 0e0h,'Replay',0efh,0ffh
	    ELSE
	    byte 0e0h,'Recording and replay',0efh,0ffh
	    ENDIF

	    byte 0ffh
	    byte 'DIRECTORY ',0e0h,'(Shift F3)',0efh,' - displays the list of records on the disk.',0ffh
	    byte 0ffh

	    IFE REPLAY
	    byte 'RECORD ',0e0h,'(F1)',0efh,' - starts a new sonar record. Can be pressed while already recording.',0ffh
	    byte 0ffh
	    ENDIF

	    byte 'PLAY ',0e0h,'(F2)',0efh,' - plays the selected record. Must be pressed twice. Start time is optional.',0ffh
	    byte 0ffh
	    byte 'STOP ',0e0h,'(F3)',0efh,' - stops replay or recording.',0ffh
	    byte 0ffh
	    byte 'PAUSE ',0e0h,'(F4)',0efh,' - pauses replay (not recording).',0ffh
	    byte 0ffh
	    byte 'CUE ',0e0h,'(Shift F2)',0efh,' - allows fast review by compressing the replayed image.',0ffh
	    byte 0ffh
	    byte 0ffh

	    IF REPLAY
	    byte 0ffh,0ffh
	    ENDIF

	    byte 'Press ',0e0h,'Q',0efh,' to cancel, or ',0e0h,'INFO',0efh,' for more',0ffh
	    byte 0feh


HelpPage4   byte 0e0h,'KEYBOARD (continued)',0bdh,'page 4',0efh,0ffh
	    byte 0ffh
	    byte 'EDIT ',0e0h,'(Shift F4)',0efh,' - copies the current screen to the disk.',0ffh
	    byte 0ffh
	    byte 0e0h,'Display controls',0efh,0ffh
	    byte 0ffh
	    byte 'ZOOM IN ',0e0h,'(F11)',0efh,' - zooms in at X2 then X4.',0ffh
	    byte 0ffh
	    byte 'ZOOM OUT ',0e0h,'(F12)',0efh,' - zooms out.',0ffh
	    byte 0ffh
	    byte 'PAN LEFT ',0e0h,'(F9)',0efh,' - pans the display to the left.',0ffh
	    byte 0ffh
	    byte 'PAN RIGHT ',0e0h,'(F10)',0efh,' - pans the display to the right.',0ffh
	    byte 0ffh
	    byte 'INV VIDEO ',0e0h,'(Shift F10)',0efh,' - inverts the current palette.',0ffh
	    byte 0ffh
	    byte 'FREEZE ',0e0h,'(Shift F9)',0efh,' - freezes the lower part of the picture: the picture scrolls',0ffh
	    byte '                    if the arrow pushes the bottom or top of the display.',0ffh
	    byte 0ffh
	    byte 'HIDE/SHOW ',0e0h,'(Shift F11)',0efh,' - supresses all screen text and event marks.',0ffh
	    byte 0ffh
	    byte 'GEOMETRY ',0e0h,'(F6)',0efh,' - cycles through normal, SRC and Map picture correction.',0ffh
	    byte 0ffh
	    byte 0ffh
	    byte 'Press ',0e0h,'Q',0efh,' to cancel, or ',0e0h,'INFO',0efh,' for more',0ffh
	    byte 0feh

HelpPage5   byte 0e0h,'KEYBOARD (continued)',0bdh,'page 5',0efh,0ffh
	    byte 0ffh
	    byte 0e0h,'Menus',0efh,0ffh
	    byte 0ffh
	    byte 'FUNC MENU ',0e0h,'(F5)',0efh,0b4h,'displays the function menu, used to set system parameters,',0ffh
	    byte 0b4h,'erase records and to eject the disk. ',0ffh
	    byte 0ffh
	    byte 'NAV MENU ',0e0h,'(Shift F5)',0efh,0b4h,'displays the navigation menu, used to set the baud rate,',0ffh
	    byte 0b4h,'speed, course and relative heading. ',0ffh
	    byte 0ffh
	    byte 'PRINT MENU ',0e0h,'(Shift F6)',0efh,0b4h,'displays the printer menu, used to set the printer type and',0ffh
	    byte 0b4h,'print mode, or to print DeskJet snapshots.',0ffh
	    ;byte 0ffh
	    byte 0e0h,'Miscellaneous',0efh,0ffh
	    byte 0ffh
	    byte 'ANNOTATE ',0e0h,'(Shift F7)',0efh,' - fixes the annotation text to the record at the arrow cursor.',0ffh
	    byte 0ffh
	    IFE REPLAY
	    byte 'EVENT MARK ',0e0h,'(Shift F8)',0efh,' - puts a numbered event mark across the record.',0ffh
	    byte 0ffh
	    byte 'LAYBACK ',0e0h,'(F7)',0efh,' - allows the user to enter the layback.',0ffh
	    byte 0ffh
	    ENDIF
	    byte 'CALC POSN ',0e0h,'(F8)',0efh,' - calculates the position of an object pointed to by the arrow.',0ffh
	    byte 0ffh

	    IF REPLAY
	    byte 'LOG POSN ',0e0h,'(F1)',0efh,' - logs the position of an object pointed to by the arrow.',0ffh
	    byte 0ffh
	    byte 'SET LOG FILE ',0e0h,'(F7)',0efh,' - selects a DOS file for logged position data.',0ffh
	    byte 0ffh
	    ENDIF

	    byte 'EXIT TO DOS ',0e0h,'(Shift F12)',0efh,' - returns to the DOS prompt.',0ffh


	    byte 0ffh
	    byte 'Press ',0e0h,'Q',0efh,' to cancel, or ',0e0h,'INFO',0efh,' for more',0ffh
	    byte 0feh

HelpPage6   byte 0e0h,'MOUSE',0bdh,'page 6',0efh,0ffh
	    byte 0ffh
	    byte 0e0h,'Left button',0efh,0ffh
	    byte 0ffh
	    byte 'When pressed, calculates the distance between the arrow cursor and the cross',0ffh
	    byte 'cursor.',0ffh
	    byte 0ffh
	    byte 'When released, leaves the cross cursor at the new position.',0ffh
	    byte 0ffh
	    byte 'When dragged (held down while the mouse is moved) outwards along a shadow,',0ffh
	    byte 'measures object height.',0ffh
	    byte 0ffh
	    byte 'Distance measurements are only valid in Map mode. Shadow measurements are',0ffh
	    byte 'valid in SRC or Map mode.',0ffh
	    byte 0ffh
	    byte 0e0h,'Right button',0efh,0ffh
	    byte 0ffh
	    byte 'When pressed, zooms in on the arrow cursor position.',0ffh
	    byte 0ffh
	    byte 0ffh
	    byte 0e0h,'End of INFO pages - see handbook for more information.',0efh,0ffh
	    byte 00fh
	    byte 0ffh
	    byte 0ffh
	    byte 0ffh
	    byte 'Press ',0e0h,'Q',0efh,' or ',0e0h,'INFO',0efh,' to cancel',0ffh
	    byte 0feh


HelpTextTable	word offset HelpPage1  ;offset list of help page text (INFO)
		word offset HelpPage2
		word offset HelpPage3
		word offset HelpPage4
		word offset HelpPage5
		word offset HelpPage6

MonthNames  byte 'Jan>'
	    byte 'Feb>'
	    byte 'Mar>'
	    byte 'Apr`'
	    byte 'May<'
	    byte 'Jun>'
	    byte 'Jul|'
	    byte 'Aug>'
	    byte 'Sep>'
	    byte 'Oct`'
	    byte 'Nov<'
	    byte 'Dec>'

	    ALIGN 2

	    IF FISHTYPE
	    ;alternative ranges
RangeChangeTable    word 0a01h		;50HF  > 100HF		    ;up
		    word 0a03h		;100HF > 150HF
		    word 0a03h		;125HF > 150hf
		    word 0384h		;150HF > 200LF or 150hf
		    word 0a85h		;200LF > 300LF
		    word 0a0ah		;300LF > None
		    word 0a0ah		;400LF > None
		    word 0a01h		;75HF  > 100HF

		    word 0a0ah		;50HF  > None		    ;down
		    word 0a00h		;100HF > 50HF
		    word 0a0ah		;125HF > None
		    word 0a01h		;150HF > 100HF
		    word 0a03h		;200LF > 150HF
		    word 0a84h		;300LF > 200LF
		    word 0a0ah		;400LF > 300LF
		    word 0a00h		;75HF  > 50HF

	    ELSE
RangeChangeTable    word 0a07h		;50HF  > 75HF		    ;up
		    word 0a03h		;100HF > 150HF
		    word 0a0ah		;125HF > None
		    word 0384h		;150HF > 200LF or 150HF
		    word 0a85h		;200LF > 300LF
		    word 0a86h		;300LF > 400LF
		    word 0a0ah		;400LF > None
		    word 0a01h		;75HF  > 100HF
		    word 0a84h		;100LF > 200LF

		    word 0a0ah		;50HF  > None		    ;down
		    word 0a07h		;100HF > 75HF
		    word 0a0ah		;125HF > None
		    word 0a01h		;150HF > 100HF
		    word 8803h		;200LF > 150HF or 100LF
		    word 0a84h		;300LF > 200LF
		    word 0a85h		;400LF > 300LF
		    word 0a00h		;75HF  > 50HF
		    word 0a0ah		;100LF > None

	    ENDIF

MonthLengths	word 0			;1st of jan
		word 31 		;	feb
		word 59 		;	mar
		word 90 		;	apr
		word 120		;	may
		word 151		;	jun
		word 181		;	jul
		word 212		;	aug
		word 243		;	sep
		word 273		;	oct
		word 304		;	nov
		word 334		;	dec

CosineTable word 65535		       ;0
	    word 65525
	    word 65495
	    word 65445
	    word 65375
	    word 65286
	    word 65176
	    word 65047
	    word 64897
	    word 64728
	    word 64539		       ;10
	    word 64330
	    word 64102
	    word 63855
	    word 63588
	    word 63302
	    word 62996
	    word 62671
	    word 62327
	    word 61965
	    word 61583		       ;20
	    word 61182
	    word 60763
	    word 60325
	    word 59869
	    word 59395
	    word 58902
	    word 58392
	    word 57864
	    word 57318
	    word 56755		       ;30
	    word 56174
	    word 55577
	    word 54962
	    word 54331
	    word 53683
	    word 53019
	    word 52338
	    word 51642
	    word 50930
	    word 50203		       ;40
	    word 49460
	    word 48702
	    word 47929
	    word 47142
	    word 46340
	    word 45524
	    word 44695
	    word 43851
	    word 42995
	    word 42125		       ;50
	    word 41243
	    word 40347
	    word 39440
	    word 38521
	    word 37589
	    word 36647
	    word 35693
	    word 34728
	    word 33753
	    word 32768		       ;60
	    word 31772
	    word 30767
	    word 29752
	    word 28729
	    word 27696
	    word 26655
	    word 25607
	    word 24550
	    word 23486
	    word 22414		       ;70
	    word 21336
	    word 20251
	    word 19161
	    word 18064
	    word 16962
	    word 15854
	    word 14742
	    word 13625
	    word 12505
	    word 11380		       ;80
	    word 10252
	    word 9121
	    word 7987
	    word 6850
	    word 5712
	    word 4571
	    word 3430
	    word 2287
	    word 1143


	;annotation arrow shape
ArrowShape  word 007fh,0041h,0021h,0021h,0041h
	    word 008dh,0113h,0220h,0140h,0080h
	    word 003eh,001eh,001eh,003eh
	    word 0072h,00e0h,01c0h,0080h

	    word 0fe00h,08200h,08400h,08400h,08200h   ;reversed
	    word 0b100h,0c880h,00440h,00280h,00100h
	    word 7c00h,7800h,7800h,7c00h
	    word 4e00h,0700h,0380h,0100h

	    word 03f0h,0208h,0204h,0202h,0201h	      ;sideways
	    word 0201h,0202h,0204h,0208h,03f0h
	    word 01f0h,01f8h,01fch,01feh
	    word 01feh,01fch,01f8h,01f0h


	;cross hair cursor shape

CursorShape word 03c0h,0240h,0240h,1ff8h,1008h	;10 outline words
	    word 1008h,1ff8h,0240h,0240h,03c0h
	    word 0180h,0180h,0180h,0ff0h	;8 inner words
	    word 0ff0h,0180h,0180h,0180h

	    word 0fc0h,1040h,2040h,4040h,8040h	      ;sideways
	    word 8040h,4040h,2040h,1040h,0fc0h
	    word 0f80h,1f80h,3f80h,7f80h
	    word 7f80h,3f80h,1f80h,0f80h

DefaultColours	byte 5,9,7,70h,7fh,70h,7fh,00h,0fh	;mono
		byte 5,9,7,70h,7fh,70h,7fh,00h,0fh	;colour

PrinterGamma	byte 0,6,10,14
		byte 16,18,20,22
		byte 24,26,28,31
		byte 35,41,50,63


PictureGamma	byte 0,0,0,0
		byte 0,0,0,0
		byte 0,0,0,0
		byte 0,0,0,0
		byte 0,0,0,0
		byte 0,0,0,0
		byte 0,0,0,0
		byte 0,0,0,0
		byte 0,0,0,0
		byte 0,0,0,0
		byte 0,0,0,0
		byte 0,0,0,0
		byte 0,0,0,1
		byte 1,1,1,1
		byte 1,1,1,1
		byte 1,2,2,2
		byte 2,2,2,2
		byte 2,3,3,3
		byte 3,3,3,3
		byte 3,4,4,4
		byte 4,4,4,5
		byte 5,5,5,5
		byte 5,6,6,6
		byte 6,6,6,7
		byte 7,7,7,8
		byte 8,8,8,9
		byte 9,9,9,10
		byte 10,10,10,11
		byte 11,11,11,12
		byte 12,12,12,13
		byte 13,13,13,14
		byte 14,14,14,15

	;KEYBOARD TRANSLATION TABLE
	;KEY CODES ARE:
	;old layout	    new layout
	;00 PAUSE	    PAUSE
	;01 PLAY	    PLAY
	;02 X		    X
	;03 Z		    Z
	;04 M		    M
	;05 ,		    ,
	;06 .		    .
	;07 SPACE	    SPACE
	;08 N		    N
	;09 B		    B
	;0A V		    V
	;0B C		    C
	;0C J		    J
	;0D K		    K
	;0E L		    L
	;0F DELETE	    DELETE
	;10 H		    H
	;11 G		    G
	;12 F		    F
	;13 D		    D
	;14 U		    U
	;15 I		    I
	;16 O		    O
	;17 P		    P
	;18 EVENT MARK	    CALC POS'N
	;19 NAV DATA	    EVENT MARK
	;1A ZOOM OUT	    ZOOM OUT
	;1B ZOOM IN	    ZOOM IN
	;1C TIME BOXES	    LAYBACK
	;1D SET SPEED	    ANNOTATE
	;1E FREEZE	    FREEZE
	;1F PAN RIGHT	    PAN RIGHT
	;20 RANGE LINES     GEOMETRY
	;21 GEOMETRY	    HIDE/SHOW
	;22 INV VIDEO	    INV VIDEO
	;23 PAN LEFT	    PAN LEFT
	;24 Y		    Y
	;25 T		    T
	;26 R		    R
	;27 E		    E
	;28 FIX TEXT	    PRINT MENU
	;29 3		    3
	;2A 6		    6
	;2B 9		    9
	;2C MOVE ARROW	    NAV MENU
	;2D 2		    2
	;2E 5		    5
	;2F 8		    8
	;30 FUNCTION	    FUNC MENU
	;31 1		    1
	;32 4		    4
	;33 7		    7
	;34 INFO	    INFO
	;35 0		    0
	;36 W		    W
	;37 Q		    Q
	;38 RECORD	    RECORD
	;39 #		    #
	;3A S		    S
	;3B A		    A
	;3C STOP	    STOP
	;3D DIRECTORY	    DIRECTORY
	;3E EDIT	    EDIT
	;3F CUE 	    CUE

KTRAN	byte 0FFH,0FFH,'XZM'	       ;__XZM
	byte ',. NB'		       ;,. NB
	byte 'VCJKL'		       ;VCJKL
	byte 0FFH,'HGFD'	       ;_HGFD
	byte 'UIOP',0FFH	       ;UIOP_
	byte 0FFH,0FFH,0FFH,0FFH,0FFH  ;_____
	byte 0FFH,0FFH,0FFH,0FFH,0FFH  ;_____
	byte 0FFH,'YTRE'	       ;_YTRE
	byte 0FFH,'369',0FFH	       ;_369_
	byte '258',0FFH,'1'	       ;258_1
	byte '47',0FFH,'0W'	       ;47_0W
	byte 'Q',0FFH,'#SA'	       ;Q_#SA
	byte 0FFH,0FFH,0FFH,0FFH       ;____

PCKeyTran   byte 0ffh,0ffh,31h,2dh,29h	    ;0
	    byte 32h,2eh,2ah,33h,2fh
	    byte 2bh,35h,0ffh,0ffh,0fh	    ;10
	    byte 0ffh,37h,36h,27h,26h
	    byte 25h,24h,14h,15h,16h	    ;20
	    byte 17h,0ffh,0ffh,0ffh,0ffh
	    byte 3bh,3ah,13h,12h,11h	    ;30
	    byte 10h,0ch,0dh,0eh,0ffh
	    byte 0ffh,0ffh,0ffh,0ffh,03h    ;40
	    byte 02h,0bh,0ah,09h,08h
	    byte 04h,05h,06h,0ffh,0ffh	    ;50
	    byte 0ffh,0ffh,07h,0ffh,38h
	    byte 01h,3ch,00h,30h,20h	    ;60
	    byte 1ch,18h,23h,1fh,0ffh
	    byte 0ffh,0ffh,0ffh,0ffh,0ffh   ;70
	    byte 0ffh,0ffh,0ffh,0ffh,0ffh
	    byte 0ffh,0ffh,0ffh,0ffh,0ffh   ;80
	    byte 0ffh,0ffh,1bh,1ah,034h
	    byte 3fh,3dh,3eh,2ch,28h	    ;90
	    byte 1dh,19h,1eh,22h,0ffh
	    byte 0ffh,0ffh,0ffh,0ffh,0ffh   ;100
	    byte 0ffh,0ffh,0ffh,0ffh,0ffh
	    byte 0ffh,0ffh,0ffh,0ffh,0ffh   ;110
	    byte 0ffh,0ffh,21h,080h,0ffh

PSRMSG	byte '50m|',0ffh
	byte '100m',0ffh
	byte '125m',0ffh
	byte '150m',0ffh
	byte '200m',0ffh
	byte '300m',0ffh
	byte '400m',0ffh
	byte '75m|',0ffh
	byte '100m',0ffh
	byte '||||',0ffh
	byte '||||',0ffh
	byte '||||',0ffh
	byte '||||',0ffh
	byte '||||',0ffh
	byte '||||',0ffh
	byte '||||',0ffh

DeskJetRanges	byte '50M '
		byte '100M'
		byte '125M'
		byte '150M'
		byte '200M'
		byte '300M'
		byte '400M'
		byte '75M '
		byte '100M'

bigmsg	byte '050'
	byte '100'
	byte '125'
	byte '150'
	byte '200'
	byte '300'
	byte '400'
	byte '075'
	byte '100'

PSGMMSG byte 'Normal{',0ffh		;RAW
	byte 'SRC{]^',0ffh,0	    ;SRC
	byte 'Map_[\',0ffh,0	    ;MAP
StatusModeMSG byte 'Live |',0ffh	   ;0
	byte 'Record',0ffh	   ;7
	byte 'Play  ',0ffh	   ;14
	byte 'Cue   ',0ffh	   ;21
	byte 'Edit  ',0ffh	   ;28
	byte 'Off   ',0ffh	   ;35
	byte 'Pause ',0ffh	   ;42
	byte 'Swap  ',0ffh	   ;49
PTMMSG	byte 'Start time?',0ffh	     ;play prompt
tspace	byte '             >',0ffh
EjectingMsg byte 'Ejecting..',0ffh

DirHeaderMessage2   byte 'Number',0b2h,'Name',0b5h,'Date',0b8h,'Start time',0bbh,'End time',0ffh
DirHeaderMessage1   byte 0e0h,'DIRECTORY of disk: ',0efh,10 dup (' '),0ffh
MediaSizeMessage    byte 0e0h,'Disk size: ',0efh,'128MB',0e0h,0ffh

DirTailMessage	byte 'Press ',0e0h,'Q',0efh,' to cancel, or ',0e0h,'DIRECTORY',0efh,' for more',0ffh
NoFilesMessage	byte 'No more records - press ',0e0h,'Q',0efh,' to cancel',0ffh
	;THIS IS THE PROPORTIONAL FONT For THE ANNOTATION TEXT
	;it is ASCII, starting at 20H
	;bits 0-2 of the last byte of each character hold
	;the width of that character excluding spacing of one (max 7)

	;small font for status bar titles and on screen annotation
	;characters are 7 deep by 8 wide, width is in byte 7 of
	;each character
FontA	byte 000h,000h,000h,000h,000h,000h,000h,003h	;space
	byte 080h,080h,080h,080h,080h,000h,080h,001h	;!
	byte 0a0h,0a0h,000h,000h,000h,000h,000h,003h	;"
	byte 050h,0f8h,050h,050h,050h,0f8h,050h,005h	;#
	byte 020h,078h,0a0h,070h,028h,0f0h,020h,005h	;$
	byte 0C8H,0C8H,010H,020H,040H,098H,098H,005H	;%
	byte 0,0,0,0,0,0,0,3				;&
	byte 0,0,0,0,0,0,0,3				;'
	byte 040h,080h,080h,080h,080h,080h,040h,002h	;(
	byte 080h,040h,040h,040h,040h,040h,080h,002h	;)
	byte 000h,000h,050h,020h,0f8h,020h,050h,005h	;*
	byte 000h,000h,020h,020h,0f8h,020h,020h,005h	;+
	byte 000H,000H,000H,000H,000H,040H,040H,082H	;,
	byte 000h,000h,000h,000h,0f8h,000h,000h,005h	;-
	byte 000H,000H,000H,000H,000H,000H,080H,001H	;.
	byte 020h,020h,040h,040h,040h,080h,080h,003h	;/
	byte 070H,088H,088H,088H,088H,088H,070H,005H	;0
	byte 040H,0C0H,040H,040H,040H,040H,0E0H,003H	;1
	byte 070H,088H,008H,070H,080H,080H,0F8H,005H	;2
	byte 070H,088H,008H,030H,008H,088H,070H,005H	;3
	byte 010H,020H,040H,080H,090H,0F8H,010H,005H	;4
	byte 0F8H,080H,0F0H,008H,008H,088H,070H,005H	;5
	byte 030H,040H,080H,0F0H,088H,088H,070H,005H	;6
	byte 0F0H,010H,010H,020H,020H,040H,040H,004H	;7
	byte 070H,088H,088H,070H,088H,088H,070H,005H	;8
	byte 070H,088H,088H,078H,008H,010H,020H,005H	;9
	byte 000H,000H,080H,000H,000H,080H,000H,001H	;:
	byte 000H,000H,040H,000H,000H,040H,080H,002H	;;
	byte 010h,020h,040h,080h,040h,020h,010h,004h	;<
	byte 000h,000h,0f0h,000h,000h,0f0h,000h,004h	;=
	byte 080h,040h,020h,010h,020h,040h,080h,004h	;>
	byte 070h,088h,008h,010h,020h,000h,020h,005h	;?
	byte 070h,088h,0b8h,0a8h,0b8h,080h,070h,005h	;@
	byte 070H,088H,088H,0F8H,088H,088H,088H,005H	;A
	byte 0F0H,088H,088H,0F0H,088H,088H,0F0H,005H	;B
	byte 070H,088H,080H,080H,080H,088H,070H,005H	;C
	byte 0F0H,088H,088H,088H,088H,088H,0F0H,005H	;D
	byte 0F8H,080H,080H,0F0H,080H,080H,0F8H,005H	;E
	byte 0F8H,080H,080H,0F0H,080H,080H,080H,005H	;F
	byte 070H,088H,080H,0B8H,088H,088H,070H,005H	;G
	byte 088H,088H,088H,0F8H,088H,088H,088H,005H	;H
	byte 0E0H,040H,040H,040H,040H,040H,0E0H,003H	;I
	byte 038H,010H,010H,010H,010H,090H,060H,005H	;J
	byte 088H,090H,0A0H,0C0H,0A0H,090H,088H,005H	;K
	byte 080H,080H,080H,080H,080H,080H,0F0H,004H	;L
	byte 088H,0D8H,0A8H,0A8H,088H,088H,088H,005H	;M
	byte 088H,088H,0C8H,0A8H,098H,088H,088H,005H	;N
	byte 070H,088H,088H,088H,088H,088H,070H,005H	;O
	byte 0F0H,088H,088H,0F0H,080H,080H,080H,005H	;P
	byte 070H,088H,088H,088H,0A8H,090H,068H,005H	;Q
	byte 0F0H,088H,088H,0F0H,0A0H,090H,088H,005H	;R
	byte 070H,088H,080H,070H,008H,088H,070H,005H	;S
	byte 0F8H,020H,020H,020H,020H,020H,020H,005H	;T
	byte 088H,088H,088H,088H,088H,088H,070H,005H	;U
	byte 088H,088H,088H,050H,050H,020H,020H,005H	;V
	byte 088H,088H,088H,088H,0A8H,0A8H,050H,005H	;W
	byte 088H,088H,050H,020H,050H,088H,088H,005H	;X
	byte 088H,088H,088H,050H,020H,020H,020H,005H	;Y
	byte 0F8H,008H,010H,020H,040H,080H,0F8H,005H	;Z
	byte 0,0,0,0,0,0,0,3				;[
	byte 0,0,0,0,0,0,0,3				;\
	byte 0,0,0,0,0,0,0,3				;]
	byte 0,0,0,0,0,0,0,3				;^
	byte 0,0,0,0,0,0,0,3				;_
	byte 0,0,0,0,0,0,0,3				;`
	byte 000h,000h,070h,090h,090h,0b0h,050h,004h	;a
	byte 080h,080h,0e0h,090h,090h,090h,0e0h,004h	;b
	byte 000h,000h,060h,090h,080h,090h,060h,004h	;c
	byte 010h,010h,070h,090h,090h,090h,070h,004h	;d
	byte 000h,000h,060h,090h,0f0h,080h,060h,004h	;e
	byte 030h,040h,040h,0e0h,040h,040h,040h,004h	;f
	byte 000h,000h,070h,090h,090h,070h,010h,064h	;g
	byte 080h,080h,080h,0e0h,090h,090h,090h,004h	;h
	byte 000h,080h,000h,080h,080h,080h,080h,001h	;i
	byte 000h,040h,000h,040h,040h,040h,040h,082h	;j
	byte 080h,080h,090h,0a0h,0c0h,0a0h,090h,005h	;k
	byte 080h,080h,080h,080h,080h,080h,040h,001h	;l
	byte 000h,000h,0f0h,0a8h,0a8h,0a8h,0a8h,005h	;m
	byte 000h,000h,0a0h,0d0h,090h,090h,090h,004h	;n
	byte 000h,000h,060h,090h,090h,090h,060h,004h	;o
	byte 000h,000h,0e0h,090h,090h,0e0h,080h,084h	;p
	byte 000h,000h,070h,090h,090h,070h,010h,01dh	;q
	byte 000h,000h,0a0h,0c0h,080h,080h,080h,003h	;r
	byte 000h,000h,070h,080h,060h,010h,0e0h,004h	;s
	byte 000h,040h,0e0h,040h,040h,040h,020h,003h	;t
	byte 000h,000h,090h,090h,090h,090h,070h,004h	;u
	byte 000h,000h,088h,088h,050h,050h,020h,005h	;v
	byte 000h,000h,088h,0a8h,0a8h,050h,050h,005h	;w
	byte 000h,000h,088h,050h,020h,050h,088h,005h	;x
	byte 000h,000h,090h,090h,090h,070h,010h,064h	;y
	byte 000h,000h,0f0h,010h,020h,040h,0f0h,004h	;z
	byte 0,0,0,0,0,0,0,3				;{
	byte 0,0,0,0,0,0,0,3				;|
	byte 0,0,0,0,0,0,0,3				;}
	byte 0,0,0,0,0,0,0,0				;~


AldenTable  byte 0		    ;send 256 bytes of rubbish to printer

	;font for deskjet dump status line
	;characters are 8x8 but rotated 180 degrees
	;bit 7 should be 0
FontB	byte 0,0,0,0,0,0,0,0				;space
	byte 0,0,0,0,0,0,0,0				;
	byte 0,0,0,0,0,0,0,0				;
	byte 0,0,0,0,0,0,0,0				;
	byte 0,0,0,0,0,0,0,0				;
	byte 0,0,0,0,0,0,0,0				;
	byte 0,0,0,0,0,0,0,0				;
	byte 0,0,0,0,0,0,0,0				;
	byte 0,0,0,0,0,0,0,0				;
	byte 0,0,0,0,0,0,0,0				;
	byte 0,0,0,0,0,0,0,0				;
	byte 0,0,0,0,0,0,0,0				;
	byte 0,0,0,0,0,0,0,0				;
	byte 0,0,0,07fh,07fh,0,0,0			;-
	byte 0,0,0,0,0,0,0,0				;
	byte 01h,03h,06h,0ch,18h,30h,60h,40h		;/
	byte 1ch,36h,63h,63h,63h,63h,36h,1ch		;0
	byte 18h,18h,18h,18h,18h,18h,1ch,18h		;1
	byte 7fh,06h,0ch,18h,30h,60h,63h,3eh		;2
	byte 3eh,63h,60h,60h,38h,60h,63h,3eh		;3
	byte 18h,18h,18h,7fh,1bh,03h,03h,03h		;4
	byte 3eh,63h,60h,63h,3fh,03h,03h,3fh		;5
	byte 3eh,63h,63h,63h,3fh,03h,03h,3eh		;6
	byte 0ch,0ch,18h,18h,30h,30h,60h,7fh		;7
	byte 3eh,63h,63h,63h,3eh,63h,63h,3eh		;8
	byte 3eh,63h,60h,60h,7eh,63h,63h,3eh		;9
	byte 00h,0ch,0ch,00h,0ch,0ch,00h,00h		;:
	byte 0,0,0,0,0,0,0,0				;
	byte 0,0,0,0,0,0,0,0				;
	byte 0,0,0,0,0,0,0,0				;
	byte 0,0,0,0,0,0,0,0				;
	byte 0,0,0,0,0,0,0,0				;
	byte 0,0,0,0,0,0,0,0				;
	byte 63h,63h,63h,7fh,63h,63h,36h,1ch		;A
	byte 3fh,63h,63h,63h,1fh,63h,63h,3fh		;B
	byte 3eh,63h,03h,03h,03h,03h,63h,3eh		;C
	byte 1fh,33h,63h,63h,63h,63h,33h,1fh		;D
	byte 7fh,03h,03h,03h,0fh,03h,03h,7fh		;E
	byte 03h,03h,03h,03h,0fh,03h,03h,7fh		;F
	byte 3eh,63h,63h,73h,03h,03h,63h,3eh		;G
	byte 63h,63h,63h,63h,7fh,63h,63h,63h		;H
	byte 8 dup (0ch)				;I
	byte 1eh,33h,60h,60h,60h,60h,60h,60h		;J
	byte 0,0,0,0,0,0,0,0				;
	byte 7fh,03h,03h,03h,03h,03h,03h,03h		;L
	byte 63h,63h,63h,63h,6bh,7fh,77h,63h		;M
	byte 63h,63h,73h,73h,6bh,67h,67h,63h		;N
	byte 3eh,63h,63h,63h,63h,63h,63h,3eh		;O
	byte 03h,03h,03h,03h,3fh,63h,63h,3fh		;P
	byte 7eh,73h,6bh,63h,63h,63h,63h,3eh		;Q
	byte 63h,63h,33h,1bh,3fh,63h,63h,3fh		;R
	byte 3eh,63h,60h,38h,0eh,03h,63h,3eh		;S
	byte 0ch,0ch,0ch,0ch,0ch,0ch,0ch,7fh		;T
	byte 3eh,63h,63h,63h,63h,63h,63h,63h		;U
	byte 1ch,1ch,36h,36h,36h,63h,63h,63h		;V
	byte 36h,7fh,6bh,63h,63h,63h,63h,63h		;W
	byte 63h,63h,36h,1ch,1ch,36h,63h,63h		;X
	byte 0ch,0ch,0ch,0ch,1ch,36h,63h,63h		;Y
	byte 0,0,0,0,0,0,0,0				;


	;large text font
	;11 high chars, width in 12th byte
	;if bit 7 of 12th byte is set, the character has a
	;descender so the character is printed 2 rows lower

FontC	byte 0,0,0,0,0,0,0,0,0,0,0,7			;space
	byte 60h,60h,60h,60h,60h,60h,60h,0,0,60h,60h,5		;!
	byte 60h,60h,0c0h,0,0,0,0,0,0,0,0,4			;"
	byte 6ch,6ch,6ch,0feh,6ch,6ch,6ch,0feh,6ch,6ch,6ch,8 ;#
	byte 010h,07ch,0d6h,0d0h,0d0h,07ch,016h,016h,0d6h,07ch,010h,8	;$
	byte 0e6h,0a6h,0ech,0ch,018h,018h,30h,30h,06eh,06ah,0ceh,8 ;%
	byte 0,0,0,30h,18h,0fch,18h,30h,0,0,0,8	;baud rate arrow
	byte 60h,60h,0c0h,0,0,0,0,0,0,0,0,4			;'
	byte 30h,60h,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,60h,30h,5 ;(
	byte 0c0h,60h,30h,30h,30h,30h,30h,30h,30h,60h,0c0h,5  ;)
	byte 060h,090h,090h,060h,0,0,0,0,0,0,0,5		;*
	byte 0,0,0,30h,30h,0fch,0fch,30h,30h,0,0,7		;+
	byte 0,0,0,0,0,0,0,060h,060h,0c0h,0,84h		;,
	byte 0,0,0,0,0,0fch,0fch,0,0,0,0,7			;-
	byte 0,0,0,0,0,0,0,0,0,060h,060h,5			;.
	byte 06h,06h,0ch,0ch,018h,018h,30h,30h,060h,060h,0c0h,8 ;/

	byte 07ch,0c6h,0c6h,0c6h,0c6h,0c6h,0c6h,0c6h,0c6h,0c6h,07ch,8	;0
	byte 018h,038h,018h,018h,018h,018h,018h,018h,018h,018h,03ch,8	;1
	byte 078h,0cch,006h,006h,006h,00ch,038h,060h,0c0h,0c0h,0feh,8	;2
	byte 078h,0cch,006h,006h,00ch,038h,00ch,006h,006h,0cch,078h,8	;3
	byte 0c0h,0c0h,0c0h,0c0h,0d8h,0d8h,0feh,018h,018h,018h,018h,8	;4
	byte 0feh,0c0h,0c0h,0d8h,0ech,0c6h,006h,006h,0c6h,06ch,038h,8	;5
	byte 03ch,066h,0c0h,0c0h,0d8h,0ech,0c6h,0c6h,0c6h,06ch,038h,8	;6
	byte 0feh,006h,00ch,00ch,018h,018h,030h,030h,060h,060h,0c0h,8	;7
	byte 038h,06ch,0c6h,0c6h,06ch,038h,06ch,0c6h,0c6h,06ch,038h,8	;8
	byte 038h,06ch,0c6h,0c6h,0ceh,07eh,036h,006h,006h,0cch,078h,8	;9

	byte 0,0,0,0,60h,60h,0,0,0,60h,60h,5		;:
	byte 0,0,0,0,0,0,0,0,0,0,0,7			;
	byte 0,0,0,0,0,0,0,0,0,0,0,3			;<
	byte 0,0,0,0f8h,0f8h,0,0,0f8h,0f8h,0,0,6	;=
	byte 0,0,0,0,0,0,0,0,0,0,0,4			;>
	byte 7ch,0c6h,0c6h,6,6,18h,30h,30h,30h,0,30h,8	;?
	byte 071h,0ffh,08eh,0,0feh,0dbh,0dbh,0dbh,0dbh,0dbh,0dbh,9 ;@ (m bar for auto)

	byte 038h,07ch,0c6h,0c6h,0c6h,0feh,0c6h,0c6h,0c6h,0c6h,0c6h,8	;A
	byte 0f8h,0cch,0c6h,0c6h,0cch,0f8h,0cch,0c6h,0c6h,0cch,0f8h,8	;B
	byte 038h,06ch,0c6h,0c0h,0c0h,0c0h,0c0h,0c0h,0c6h,06ch,038h,8	;C
	byte 0f0h,0cch,0c6h,0c6h,0c6h,0c6h,0c6h,0c6h,0c6h,0cch,0f0h,8	;D
	byte 0feh,0c0h,0c0h,0c0h,0c0h,0fch,0c0h,0c0h,0c0h,0c0h,0feh,8	;E
	byte 0feh,0c0h,0c0h,0c0h,0c0h,0fch,0c0h,0c0h,0c0h,0c0h,0c0h,8	;F
	byte 038h,06ch,0c6h,0c0h,0c0h,0c0h,0ceh,0c6h,0c6h,06eh,03ah,8	;G
	byte 0c6h,0c6h,0c6h,0c6h,0c6h,0feh,0c6h,0c6h,0c6h,0c6h,0c6h,8	;H
	byte 0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,3	;I
	byte 006h,006h,006h,006h,006h,006h,006h,006h,0c6h,06ch,038h,8	;J
	byte 0c6h,0cch,0d8h,0f0h,0e0h,0c0h,0e0h,0f0h,0d8h,0cch,0c6h,8	;K
	byte 0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,0feh,8	;L
	byte 0c3h,0e7h,0ffh,0dbh,0c3h,0c3h,0c3h,0c3h,0c3h,0c3h,0c3h,9	;M
	byte 0c6h,0e6h,0e6h,0d6h,0d6h,0ceh,0ceh,0c6h,0c6h,0c6h,0c6h,8	;N
	byte 038h,06ch,0c6h,0c6h,0c6h,0c6h,0c6h,0c6h,0c6h,06ch,038h,8	;O
	byte 0f8h,0cch,0c6h,0c6h,0cch,0f8h,0c0h,0c0h,0c0h,0c0h,0c0h,8	;P
	byte 038h,06ch,0c6h,0c6h,0c6h,0c6h,0c6h,0d6h,0ceh,06ch,036h,8	;Q
	byte 0f8h,0cch,0c6h,0c6h,0cch,0f8h,0cch,0c6h,0c6h,0c6h,0c6h,8	;R
	byte 03ch,066h,0c0h,0c0h,060h,038h,00ch,006h,006h,0cch,078h,8	;S
	byte 0ffh,018h,018h,018h,018h,018h,018h,018h,018h,018h,018h,9	;T
	byte 0c6h,0c6h,0c6h,0c6h,0c6h,0c6h,0c6h,0c6h,0c6h,06ch,038h,8	;U
	byte 0c6h,0c6h,0c6h,0c6h,06ch,06ch,06ch,06ch,038h,038h,038h,8	;V
	byte 0c3h,0c3h,0c3h,0c3h,0c3h,0c3h,0dbh,0dbh,0ffh,07eh,066h,9	;W
	byte 0c6h,0c6h,06ch,06ch,038h,010h,038h,06ch,06ch,0c6h,0c6h,8	;X
	byte 0c3h,0c3h,066h,066h,03ch,018h,018h,018h,018h,018h,018h,9	;Y
	byte 0feh,006h,00ch,00ch,018h,018h,030h,060h,060h,0c0h,0feh,8	;Z

	byte 0,0,1,4,0ch,01fh,0ch,4,1,0,0,8			;[
	byte 40h,0e0h,0f0h,44h,46h,0ffh,46h,44h,0f0h,0e0h,40h,8	;\
	byte 0,0,0,4,0ch,01fh,0ch,4,0,0,0,8			;]
	byte 0,0,0,4,6,0ffh,6,4,0,0,0,8	;^
	byte 0,0,0,0,0,0,0,0,0,0,0,2			;_
	byte 0,0,0,0,0,0,0,0,0,0,0,5			;`
	byte 0,0,0,0,78h,0cch,0ch,07ch,0cch,0cch,74h,7	;a
	byte 0c0h,0c0h,0c0h,0c0h,0f8h,0cch,0cch,0cch,0cch,0cch,0f8h,7	;b
	byte 0,0,0,0,78h,0cch,0c0h,0c0h,0c0h,0cch,78h,7	;c
	byte 0ch,0ch,0ch,0ch,7ch,0cch,0cch,0cch,0cch,0cch,7ch,7 ;d
	byte 0,0,0,0,78h,0cch,0cch,0f8h,0c0h,0cch,78h,7	;e
	byte 18h,30h,60h,60h,60h,0f0h,60h,60h,60h,60h,60h,6 ;f
	byte 0,0,78h,0cch,0cch,0cch,0cch,7ch,0ch,0ch,38h,87h	;g
	byte 0c0h,0c0h,0c0h,0c0h,0f8h,0cch,0cch,0cch,0cch,0cch,0cch,7	;h
	byte 0,0,0c0h,0,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,3 ;i
	byte 30h,0,30h,30h,30h,30h,30h,30h,30h,60h,0c0h,85h	;j
	byte 0c0h,0c0h,0c0h,0c0h,0cch,0d8h,0f0h,0e0h,0f0h,0d8h,0cch,7 ;k
	byte 0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,0c0h,3 ;l
	byte 0,0,0,0,0feh,0dbh,0dbh,0dbh,0dbh,0dbh,0dbh,9   ;m
	byte 0,0,0,0,0d8h,0ech,0cch,0cch,0cch,0cch,0cch,7	;n
	byte 0,0,0,0,78h,0cch,0cch,0cch,0cch,0cch,78h,7	;o
	byte 0,0,0f8h,0cch,0cch,0cch,0cch,0f8h,0c0h,0c0h,0c0h,87h ;p
	byte 0,0,07ch,0cch,0cch,0cch,0cch,07ch,0ch,0ch,06h,87h	;q
	byte 0,0,0,0,0d8h,0f0h,0c0h,0c0h,0c0h,0c0h,0c0h,6 ;r
	byte 0,0,0,0,78h,0cch,0c0h,78h,0ch,0cch,78h,7	;s
	byte 0,060h,060h,060h,0f8h,060h,060h,060h,060h,060h,038h,6 ;t			;t
	byte 0,0,0,0,0cch,0cch,0cch,0cch,0cch,0cch,7ch,7 ;u
	byte 0,0,0,0,0c6h,0c6h,0c6h,6ch,6ch,38h,38h,8	;v
	byte 0,0,0,0,0c3h,0c3h,0c3h,0c3h,0dbh,0ffh,066h,9	;w
	byte 0,0,0,0,0cch,0cch,078h,030h,078h,0cch,0cch,7	;x
	byte 0,0,0cch,0cch,0cch,0cch,0cch,7ch,0ch,0ch,38h,87h	;y
	byte 0,0,0,0,0fch,0ch,018h,030h,060h,0c0h,0fch,7	;z
	byte 0,0,0,0,0,0,0,0,0,0,0,1			;{
	byte 0,0,0,0,0,0,0,0,0,0,0,8			;|




FontD	word 0001111100000000b	;big fonts for bigrng
	word 0011111110000000b	;the most significant 11 bits of
	word 0110000011000000b	;each line are used
	word 1100000001100000b
	word 1100000001100000b
	word 1100000001100000b
	word 1100000001100000b
	word 1100000001100000b
	word 1100000001100000b
	word 1100000001100000b
	word 1100000001100000b
	word 1100000001100000b
	word 1100000001100000b
	word 0110000011000000b
	word 0011111110000000b
	word 0001111100000000b

	word 0000000011000000b
	word 0000000111000000b
	word 0000001111000000b
	word 0000000011000000b
	word 0000000011000000b
	word 0000000011000000b
	word 0000000011000000b
	word 0000000011000000b
	word 0000000011000000b
	word 0000000011000000b
	word 0000000011000000b
	word 0000000011000000b
	word 0000000011000000b
	word 0000000011000000b
	word 0000000011000000b
	word 0000000011000000b

	word 0011111100000000b
	word 0111111110000000b
	word 1100000011000000b
	word 0000000001100000b
	word 0000000001100000b
	word 0000000001100000b
	word 0000000001100000b
	word 0000000011000000b
	word 0001111110000000b
	word 0011111100000000b
	word 0110000000000000b
	word 1100000000000000b
	word 1100000000000000b
	word 1100000000000000b
	word 1111111111100000b
	word 1111111111100000b

	word 0011111100000000b
	word 0111111110000000b
	word 1100000011000000b
	word 0000000001100000b
	word 0000000001100000b
	word 0000000011000000b
	word 0000011110000000b
	word 0000011111000000b
	word 0000000011000000b
	word 0000000001100000b
	word 0000000001100000b
	word 0000000001100000b
	word 1100000001100000b
	word 1100000011000000b
	word 0111111110000000b
	word 0011111100000000b

	word 0000110000000000b
	word 0000110000000000b
	word 0001100000000000b
	word 0001100000000000b
	word 0011000000000000b
	word 0011000000000000b
	word 0110000000000000b
	word 0110000000000000b
	word 1100000000000000b
	word 1100001100000000b
	word 1111111111100000b
	word 1111111111100000b
	word 0000001100000000b
	word 0000001100000000b
	word 0000001100000000b
	word 0000001100000000b

	word 1111111111000000b
	word 1111111111000000b
	word 1100000000000000b
	word 1100000000000000b
	word 1100000000000000b
	word 1101111100000000b
	word 1111111110000000b
	word 1110000011000000b
	word 0000000001100000b
	word 0000000001100000b
	word 0000000001100000b
	word 0000000001100000b
	word 1100000001100000b
	word 1100000011000000b
	word 0111111110000000b
	word 0011111100000000b

	word 16 dup (?)

	word 0111111111100000b
	word 0111111111100000b
	word 0000000001100000b
	word 0000000001100000b
	word 0000000011000000b
	word 0000000011000000b
	word 0000000110000000b
	word 0000000110000000b
	word 0000001100000000b
	word 0000001100000000b
	word 0000011000000000b
	word 0000011000000000b
	word 0000110000000000b
	word 0000110000000000b
	word 0001100000000000b
	word 0001100000000000b




dotpic	word 0000000000000000b	       ;this is the dot graphic used
	word 1100000000000011b	       ;to display range windows
	word 1111000000001111b	       ;it is accessed bytewise
	word 1111100000011111b	       ;hence the byte reversal
	word 1111110000111111b
	word 1111110000111111b
	word 1111111001111111b
	word 1111111001111111b
	word 1111111001111111b
	word 1111111001111111b
	word 1111110000111111b
	word 1111110000111111b
	word 1111100000011111b
	word 1111000000001111b
	word 1100000000000011b
	word 0000000000000000b

	IF FORCEEXPORT

	;bitmap header
BitmapHeader	byte 'BM'	       ;file is a BitMap
		dword 153718	       ;640x480, 2 pixels/byte+118(header+CM)
		dword 0 	       ;reserved
		dword 118	       ;size of header+colour map
		dword 028h	       ;size of picture info header
		dword 640	       ;width in pixels
		dword 480	       ;height in pixels
		word 1		       ;number of planes
		word 4		       ;bits per pixel
		dword 0 	       ;no compression
		dword 153600	       ;bytes in bitmap
		dword 0 	       ;X pixels per metre
		dword 0 	       ;Y pixels per metre
		dword 0 	       ;all colour map entries used
		dword 10h	       ;16 colours needed

	ENDIF


ColourTable	byte 0,0,0		;grey scale black
		byte 4,4,4
		byte 8,8,8
		byte 12,12,12

		byte 16,16,16
		byte 20,20,20
		byte 24,24,24
		byte 28,28,28

		byte 32,32,32
		byte 36,36,36
		byte 40,40,40
		byte 44,44,44

		byte 48,48,48
		byte 52,52,52
		byte 56,56,56
		byte 60,60,60		;white

		;false colour
		;    R	G  B
		byte 00,00,00		;(black)	0
		byte 08,04,00		;		1
		byte 16,08,00		;		2
		byte 24,12,00		;		3

		byte 32,16,00		;		4
		byte 40,20,00		;	5
		byte 24,24,24		;(40% grey)	6
		byte 48,24,00		;		7

		byte 32,32,32		;(54% grey)	8
		byte 48,28,00		;	9
		byte 40,40,40		;(66% grey)	a
		byte 48,32,00		;		b

		byte 48,36,00		;	c
		byte 48,40,00		;		d
		byte 48,44,00		;		e
		byte 60,60,60		;(white)	f

    ;false colour amber proportions (in 16ths) are
    ;intensity	R   G	B	C   M	Y
    ;0		0   0	0	15  15	15
    ;1		2   1	0	13  14	15
    ;2		4   2	0
    ;3		6   3	0
    ;4		8   4	0
    ;5		10  5	0
    ;6		10  5	0
    ;7		12  6	0
    ;8		12  7	0
    ;9		12  7	0
    ;10 	12  8	0
    ;11 	12  8	0
    ;12 	12  9	0
    ;13 	12  10	0
    ;14 	12  11	0
    ;15 	12  11	0




ScreenGamma byte 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15	;monochrome
	    byte 1,1,2,3,4,4,6,6,8,8,10,11,12,13,14,14	;false colour


SCSITableEnd	byte 0


DESCRP	WORD 0000H		       ;00=NULL SEGMENT
	byte 00H,00H,00H,00H,00H,00H

	WORD 0000H		       ;08=CODE SEGMENT CS
	byte 00H,00H,00H,9aH,00H,00H

	WORD 0000H		       ;10=VARIABLE DATA SEGMENT DS
	byte 00H,00H,00H,93H,00H,00H

	WORD 0000H		       ;18=STACK SEGMENT SS
	byte 00H,00H,00H,97H,00H,00H

	WORD 0FFFFH		       ;20=VIDEO SEGMENT ES
	byte 00H,00H,0AH,93H,00H,00H

	WORD 0000H		       ;28=STATIC DATA SEGMENT FS
	byte 00H,00H,00H,91H,00H,00H

	WORD 0ffffH		       ;30=PRINTER BUFFER
	byte 00H,00H,00H,93H,041H,00H


FSFIN:	;END OF STATIC DATA SEGMENT
FSEG	ENDS

DSEG	SEGMENT USE16

DSBEG:	;START OF VARIABLE DATA SEGMENT

SRCBuffer   byte 3840 DUP (?)	       ;BUFFER For Map and SRC MODE
TMPBUF	byte 640 DUP (?)
DIRSEC	byte 4096 DUP (?)	       ;DIRECTORY SECTORS
PRNBUF	byte 2048 DUP (?)	       ;PRINTER BUFFER For SRC
SRCHBF	byte 4096 DUP (?)	       ;SEARCH BUFFER
ScanBuffer  byte 10240 dup (0)

IFE DEMO
ConvertBuffer byte 2048 dup (?)		;buffer for playback of v4 records
ENDIF

CurrentCluster	DWORD 0000H	       ;current Play\Record cluster
TempCurCluster	DWORD 0000H	       ;HOLDS CurrentCluster DURING edit
TempWCluster	DWORD 0000H
StopCluster	DWORD 00H	       ;last cluster of current record
StartCluster	DWORD 00H	       ;first cluster of current record
SearchStep	DWORD 0000H	       ;SEARCH STEP
AltitudeSquared	DWORD 00H	       ;SQUARE OF Altitude
NavNorthings1	dword 0
NavEastings1	dword 0
NavNorthings2	dword 0
NavEastings2	dword 0
LatitudeFix	dword 0
LongitudeFix	dword 0
ErrorEAX    dword 0
ErrorEBX    dword 0
ErrorECX    dword 0
ErrorEDX    dword 0
ErrorESI    dword 0
ErrorEDI    dword 0
ErrorFGS    dword 0
ErrorT1     dword 0
ErrorT2     dword 0
CacheCluster	dword 0
SquaresTable	DWORD 2048 DUP (?)	;2048 32-BIT SQUARES for map mode
LogsTable   byte 256 dup (?)
PBufAd	dword 0000H
TNavBuffer	byte 64 dup (0ffh)	;nav buffer for redraw
NavDataBuffer	byte 64 dup (0ffh)     ;64 bytes of nav data
NavIntBuffer	byte 64 dup (0ffh)     ;64 bytes of nav data
NavDataString	byte 64 dup (0ffh)
CompNavString	byte 64 dup (0ffh)	;compressed nav data
UpperFixBuffer	byte 64 dup (0ffh)
LowerFixBuffer	byte 64 dup (0ffh)
BannerCount	word 0
NavDataNumber	word 0
TempWSegment	word 0
TroubleSelector word 0
LowerLine   word 0
UpperLine   word 0
CursorLine  word 0
NorthRatio  word 0
EastRatio   word 0
NavLayback  word 0
CableScope  word 0
NavOffset   word 0
NavCourse  word 0
CursorLayback	word 0
TrueLayback word 0
TrueOffset  word 0


UpdateLength	word 0			;size of software update
DLINE	WORD 0000H		       ;THE LAST LINE PRINTED
LineLength	WORD 0000H		       ;NO. OF BYTES PER SCAN
DNUM	WORD 0000H		       ;NO. OF BYTES RECIEVED SO FAR/SCAN
CLINE	WORD 0000H		       ;THE LINE CURRENTLY BEING RECIEVED
RLINE	WORD 0000H		       ;THE LINE BEING REDRAWN
RELINE	WORD 0000H		       ;RECORD LINE
RaddR	WORD 0000H		       ;and ITS SCREEN addRESS
RCOUNT	WORD 0000H		       ;THE NUMBER OF LINES LEFT TO REDRAW
RedrawAddress	WORD 0000H	       ;SCREEN addR OF CURRENT REDRAW LINE
DoneLineAddress word 0			;address of features printed by pdline
TaddR	WORD 0000H
HaddR	WORD 0000H
VaddR	WORD 0000H
naddr	word 0000h		       ;nav data redraw address
ARROW	WORD 0000h		       ;addRESS OF ANNOTATION ARROW
LPTAddress  word 0		       ;port address of LPT1
CursorAddress	word 0000h
RemoveAddress	word 0000h
WindowTextPointer	WORD 0000H	 ;HELP TEXT POINTER
WSPointer	WORD 0000H		       ;HELP SCREEN POINTER
CCOUNT	WORD 0000H		       ;LINE COUNT For COPY
OLINE	WORD 0000H		       ;CURRENT PRINTER LINE
FWDINC	WORD 001H		       ;FWD SEC COUNT
DIRADR	WORD 0000H
VENUM	word 00H
EventNumber word 00H		       ;event mark number (bcd)
SequenceCount	word 0		       ;sequence counter
MouseXCoord word 00H		       ;mouse hotspot x range 16-623
MouseYCoord word 00H		       ;mouse hotspot y range 0-441
CursorXCoord	word 00h
CursorYCoord	word 00h
EditSize    word 0000h		       ;number of clusters in current edit
ScreenLineMap	word 512 dup (0)       ;map of which screen lines are
				       ;showing which buffer lines
RedrawMapLine	word 0000h	       ;redraw screen map line
PrinterDriver	word 0000h	       ;address of current printer driver
ScrollDepth	word 0000h	       ;number of bytes to scroll
NewlineRemain	word 0000h	       ;scaling remainders
RedrawRemain	word 0000h
PrinterRemain	word 0000h
CompressionFactor  word 0000h
HPLineCount word 0000h		       ;no. of lines sent to HP printer
ShadowStart	word 0000h
LogFileHandle	word 0
ScanLine    word 0
ScreenAddress	word 0
ErrorLength word 0
NewLineLength	word 0
CoaxPulse   word 0
Sounding    word 0			;depth sounding in 0.1 metres
LogValue    word 0
SCSI6Command byte 0,0,0,0,0,0
SCSI10Command	byte 0,0,0,0,0,0,0,0,0,0

	;byte variables
AlarmControl	byte 0		       ;1=enable alt. alarm, 0=mask it
AlarmFlag  byte 00H		       ;bit 0=stop alarm, 1=altitude alarm
AlarmHistory	byte 00
AllowNewGLL byte 0
Altitude    byte 00H			;Altitude ABOVE SEABED
AntiBounce  byte 0
ArrowColour byte 0		       ;colour of centre of arrow
AutoRepDel  byte 0
BatteryVoltage	byte 00H	       ;towfish battery voltage
BaudRate    byte 0		       ;1=1200 2=2400 ... 5=19200
BHead	byte 00H		       ;HEAD OF RedrawAnBuffer
BTail	byte 00H		       ;TAIL OF RedrawAnBuffer
CharC	byte 00H		       ;HELP COLUMN COUNT
ClockTick   byte 0
ColourSelect	byte 0		       ;upper 2 bits of colour reg. offset
CueLineCount	byte 00H	       ;FWD FLAG COUNT
CurPly	byte 00H		       ;CURRENT PLAY NUMBER
CurRec	byte 00H		       ;CURRENT RECORD NUMBER
CursorAngle byte 0
DebugCount  byte 0
DirFlg	byte 00H		       ;1=DIRECTORY PRINT DONE
DirNum	byte 00H		       ;RECORD NO. BEING PRINTED
ErrorFade   byte 0
FaultCount  byte 0
FeatureFlag	byte 00H	       ;FEATURE REQUEST FLAG
	;BIT	    MEANING
	;0	    event mark
	;1	    annotation text present
	;2	    minute mark
	;3	    nav data valid
	;4	    fourth line flag
	;5	    skipped feature flag
	;6	    record delineation mark
	;7	    altitude mark
ForWAD	byte 00H
FourP	byte 00H		       ;X4 PAN OFFSET
FreezeMode  byte 00H		       ;BIT 0 1=FREEZE ON, 0=FREEZE OFF
HelpC	byte 00H		       ;HELP PAGE number
HFlag	byte 00H
InitRedraw	byte 00H
KeyBufHead  byte 0
KeyBufTail  byte 0
KeyCode byte 0			       ;code of last key pressed
LastData    byte 0
LastKeyCode	byte 00h	       ;used to scan keypad
LaybackCount	byte 0		       ;controls flash of speed and layback
LinkError   byte 00h		       ;set if bad line is recieved
LogMode byte 0
LookBackScrl	byte 00h		;1=up 2=down
ManualAltitude	byte 0			;1 if in manual adjust mode
MediaType   byte 00		       ;0=128MB 1=230MB 2=640Mb
MouseRate   byte 00		       ;mouse sensitivity
NavAngle    byte 0		       ;heading relative to course
NavDataReady	byte 00 	       ;1 if new nav data in
NewCurZoom  byte 0
NewRangeFlag	byte 00H	       ;1 IF NEW RANGE FOUND
NewValues  byte 0		       ;set when voltage changes
NorthDegrees	byte 0
PaletteRegNo	byte 0
PassCount   byte 00h
PeriodTick  byte 0
PrinterNumber	byte 00h	       ;number of current printer
PrintTest   byte 0
PTickCount  byte 0
RangeNumber	byte 00H	       ;0=50M 1=100M 2=125M 3=150m 4=200M
				       ;5=300m 6=400m, 7=75m bit 7=freq.1=LF
				       ;8=100m lf
ReadFormat  byte 0
Redraw	byte 00H
RedrawLine  byte 00h		       ;1=pline is doing a redraw line
RedrawZoom  byte 00		       ;zoom and pan used for
RedrawPan   byte 00		       ;redraw lines
RegisterNumber	byte 0
RetryCount  byte 00h		       ;no of retrys for Write16
SavedFreeze byte 0			;freeze mode saved during cursor zoom
ScreenGeometry	byte 00H	       ;0=normal, 1=SRC, 2=Map
ScreenZoom  byte 00H		       ;Current zoom factor
ScreenPan   byte 00H		       ;Current pan position (0-15)
ScrollDrop  byte 00H		       ;NUMBER OF LINES PRINTED BY PLINE
SetTMF	byte 00H		       ;1 IF TIME SET MODE (ALSO PLAY TIME)
ShiftKeyDown	byte 00h	       ;1 if shift key is down
SkippedFlag	byte 00H	       ;bit 5(20h)=feature present
SMin	byte 00H
SHour	byte 00H		       ;SEARCH TIME For PLAY
SnapshotPending   byte 0
Speed	byte 00H		       ;SPEED in 0.1m/s
StCap	byte 00H		       ;REMANING STORE CAPACITY
StorageMode	byte 00H		       ;BIT 0=PLAY BIT 1=RECORD
TAltitude byte 00H
TargetRange byte 0
TestCount   byte 0
TelemetryReady	byte 01H		;IF 1, NEW TelemetryData AVAILABLE
TextColour	byte 00h	       ;colour of the small text
TFlag	byte 00H
TMins	byte 00H
TNavFlag    byte 00h		       ;1 if nav data waiting for redraw
TTime	word 00H
TVNumber    word 0
UpdateDone  byte 0		       ;set to 1 by RTC interrupt
VFlag	byte 00H
WriteZoom   byte 00		       ;pan and zoom settings used
WritePan    byte 00		       ;for writeln routine

KeyboardBuffer	byte 10h dup (0)       ;16 byte buffer
RedrawAnBuffer	byte 080H DUP (0)	;REDRAW BUFFER For ANNOTATION

HOURS	byte 00H		       ;CURRENT TIME
MINUTES byte 00H
SECONDS byte 00H
ARRBUF	byte 120 DUP (0)	       ;BACKGROUND STORE For PrintArrow
CursorBuffer	byte 120 dup (0)
TelemetryData	byte 24 DUP (0)	       ;Telemetry DATA
PulleyString	byte '+0000.0   '

PAUSEF	byte 00H		       ;PAUSE FLAG
EditOnFlag	byte 00H	       ;1=edit mode on
SwapMode    byte 0		       ;1=swap mode on
HBOXC	byte 00H		       ;Altitude BOX COUNTER
HBoxReady   byte 00h
CacheOff    byte 00h
DisplayFlags	byte 0
	;bit	function
	;0	annotation
	;1	altitude boxes
	;2	0=hide nav data
	;3	event marks
	;4	0=show position only
	;5	speed display
	;6	range lines
	;7	palette
HideShowFlag	byte 00
BannerPrinted	byte 0
UpDownCount byte 0
DiskAlarm   byte 0		       ;set if alarm has been set off
CoaxPower  byte 0
RangeChange byte 0		       ;set on third byte of monitor data
SonarWasOn  byte 00H
SonarIsOn   byte 00H		       ;set when a byte is recieved
SStartSign  byte 00h
AutoStart   byte 0
DeskJetDPI  byte 0
PulleyInstalled	byte 0
WasAPulley  byte 0
INVPAL	byte 00H		       ;0fh=normal, 00h=inverse palette
DSTAT	byte 00H		       ;OPTICAL disk SCSI STATUS
ContrastMul byte 0
ContrastOff byte 0
ContrastNumber byte 0

	;screen colours 0(light)-15(dark)
WindowFrameLight    byte 0
WindowFrameDark     byte 0
WindowBackground    byte 0
LightStatText	byte 0
DarkStatText	byte 0
LightFuncText	byte 0
DarkFuncText	byte 0
AnnotationBack	byte 0
AnnotationFore	byte 0


MonoScheme  byte 9 dup (0)
ColourScheme	byte 9 dup (0)

WindowFlag	byte 00h	       ;each bit in this byte shows
				       ;if a window is active
	;bit 0=function menu active
	;bit 1=directory active
	;bit 2=help pages active
	;bit 3=big range number active
	;bit 4=printer function menu active
	;bit 5=nav data menu active

RSBUFF	byte 18 DUP (0)	       ;BUFFER For REQUEST SENSE DATA

LASTRN	byte 00H		       ;LAST RECORD PLAYED

MOUSEF	byte 00H		       ;flags for mouse driver
CurseF	byte 00H		       ;flags for mouse driver
MouseMoved  byte 00H		       ;1=mouse has moved
MouseShowing	byte 00h	       ;1=cursor is visible
HideMouse   byte 0
PS2Mouse    byte 0		       ;0=none, 1=present
PS2Count    byte 0
LeftButton  byte 00H		       ;1=left button has been pressed
RightButton byte 00H		       ;1=right button has been pressed
JustPressedR byte 00h		       ;1=right button is already down
JustPressedL byte 00h		       ;1=left button is already down

LTime	word 0
LRange	byte 0
LAltitude   byte 0
LSpeed	byte 0
LVNumber    word 0
LAnnotation byte 11 dup (0)
LAnPosition byte 0
LFeatures   byte 0
LSounding   word 0


FixType	byte 0
EastNorth   byte 0
ANBUFF	byte 13 DUP (0FFH)	       ;BUFFER For ANNOTATION TEXT
ANCUR	byte 00H		       ;POINTER TO LAST A.C. ENTERED
InfoMessage byte 20 dup (0ffh)
ETBUFF	byte 0,0,0,0,0,0FFH	       ;TIME EXPand BUFFER BCD TO TEXT
OHEAD	byte 00H		       ;0-31
OTAIL	byte 00H		       ;0-31
SwitchTime  byte 0
SequenceFlag	byte 00H	       ;bit 0=sequence	 bit 1=repeat
SnapNumber  byte 0
SnapCount   byte 0
TraceColour byte 0
PTraceColour byte 0
AnnotationUsed	byte 00H	       ;1 IF ANNOTATION USED
FuncZCount	byte 00h	       ;counter for erase disk
FuncUCount	byte 00h	       ;counter for erase last record
PrinterMode	byte 00H	       ;0=FULL 1=LEFT 2=RIGHT 3=centre
TempPrintMode	byte 00h	       ;holds PrinterMode during HP dump
GammaCorrection byte 00h	       ;printer gamma correction flag
PREPT	byte 00H		       ;PRINT LINE REPEAT
PFLAG	byte 00H		       ;1=PRINTER ON
REMAIN	byte 00H
LDZERO	byte 00H
SCSIID	byte 00h		       ;scsi drive id byte (auto-find)
DriveError  byte 0
BitmapError byte 0
ModeSenseBuffer byte 30h dup (0)	;buffer for SCSI mode sense

testmsg byte 128 dup (0)
	byte 0ffh
HPConfigText	byte 64 dup (?)


DSPROTF:

DTABLE	DescriptorTable <>		       ;GDT and IDT REGISTERS ARE
ITABLE	DescriptorTable <>		       ;LOADED FROM HERE

HandlerOffset	word 0		       ;address of XMS handler
HandlerSegment	word 0

BufferSize  word 0			;size of buffer (no. of scan lines)
BufferLimit word 0			;last line in buffer (BufferSize-1)
LastSelector	word 0			;value of last selector
					;(BufferSize+7)*8

XMSErrorMsg1	byte 'No XMS driver installed!',10,13,'$'
XMSErrorMsg2	byte 'Not enough extended memory!',10,13,'$'
XMSErrorMsg3	byte 'Already in protected or virtual V86 mode!',10,13,'$'
XMSErrorMsg4	byte 'No CM800 controller card found!',10,13,'$'
NoFileMsg   byte 'File not found!',10,13,'$'
SyntaxMsg   byte 'Syntax: CMDEMO  filename ',10,13,'$'

NoDriveMsg  byte 'No response from drive!',10,13,'$'
LogFileName byte 'DEFAULTS.LOG',0
LogBuffer   byte 82 dup (' ')
UpdateName  byte 'CMUPDATE.EXE',0

MaskValue1  byte 0
MaskValue2  byte 0

RMTABLE	DescriptorTable <03ffh,0>	       ;real mode IDTR

TestFile    byte 'TESTDATA.DAT',0
Filename    byte '            ',0
BMPFilename    byte 'BITMAP  .BMP',0
ColourFile  byte 'CM800.COL',0
XMSTable    dword 32768	       ;copy length
;table for XMS function 0bh
SourceHandle	word 0		       ;0 for DOS memory

SourceOffset	word 0
SourceSegment	word 0
XMSHandle   word 0

XMSOffset   dword 0
;end of table
XMSAddress  word 0
FileHandle  word 0

LoadCount   byte 0

	IF DEMO EQ 1
TransferBuffer	byte 32768 dup (?)
	ENDIF

LineBuffer  byte 320 dup (0)

	IFE FORCEEXPORT
	;bitmap header
BitmapHeader	byte 'BM'	       ;file is a BitMap
		dword 153718	       ;640x480, 2 pixels/byte+118(header+CM)
		dword 0 	       ;reserved
		dword 118	       ;size of header+colour map
		dword 028h	       ;size of picture info header
		dword 640	       ;width in pixels
		dword 480	       ;height in pixels
		word 1		       ;number of planes
		word 4		       ;bits per pixel
		dword 0 	       ;no compression
		dword 153600	       ;bytes in bitmap
		dword 0 	       ;X pixels per metre
		dword 0 	       ;Y pixels per metre
		dword 0 	       ;all colour map entries used
		dword 10h	       ;16 colours needed
		ENDIF

ColourMap	dword 16 dup (0)       ;G, R, B and null. All 0-255




DSFIN:	;END OF VARIABLE DATA SEGMENT
DSEG	ENDS

PSEG	SEGMENT USE32
	;printer buffer segment part 1
PrinterBuffer	byte 20000h dup (?)	;64k

PSEG	ENDS


GSEG	SEGMENT USE16

	byte 4096 dup (?)



GSEG	ENDS

GDTS	SEGMENT USE16		       ;GLOBAL DESCRIPTor TABLE SEGMENT
GSBEG:
NULL	WORD 0000H		       ;00=NULL SEGMENT
	byte 00H,00H,00H,00H,00H,00H
CODES	WORD 0000H		       ;08=CODE SEGMENT CS
	byte 00H,00H,00H,9DH,00H,00H
DATAS	WORD 0000H		       ;10=VARIABLE DATA SEGMENT DS
	byte 00H,00H,00H,93H,00H,00H
STAKS	WORD 0000H		       ;18=STACK SEGMENT SS
	byte 00H,00H,00H,97H,00H,00H
VIDEO	WORD 0FFFFH		       ;20=VIDEO SEGMENT ES
	byte 00H,00H,0AH,93H,00H,00H
STATS	WORD 0000H		       ;28=STATIC DATA SEGMENT FS
	byte 00H,00H,00H,91H,00H,00H
testS	WORD 0ffffh		       ;30=Printer segment
	byte 00H,00H,00H,93H,041H,00H
SCNAS	byte 4096*8 DUP (?)	       ;0EA0=LAST BUFFER SEGMENT GS
GSFIN:
GDTS	ENDS

IDTS	SEGMENT USE16		       ;interrupt DESCRIPTor TABLE SEGMENT
ISBEG:
	byte 0180H DUP (0)	       ;ALL BLANK TO START WITH
ISFIN:
IDTS	ENDS
	END BEGIN
