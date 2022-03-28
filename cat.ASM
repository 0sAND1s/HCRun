;File listing program for HC
;George Chirtoaca, george.chirtoaca(@)gmail(.)com, March 2022
;
;The purpose of this program is to have a fast file listing, that includes hidden files and also shows the file size and file attributes using colours on screen.
;File selection will be possible with arrow keys, to select BASIC programs and run them, making it usefull as "run" program for auto-run on HC floppy disks. That's why it tries to be small and fast.
;Reading the exact file size and file type requires opening up each file, which is slow, so it's not performed. The aproximate file size provided (rounded at 128 bytes) can be used as a hint to guess the file type.
;Smaller files should be the BASIC loaders (around 256 bytes). SCREEN$ files are 7168 bytes. Larger files are code files usually. Files bigger than 64K are shown with file size in kilobytes.
;Can display up to 128 files (max supported by HC BASIC file system), grouped in up to 3 pages, 44 files per page. Most disks will have one page listing, quickly showing up all disk info on one screen.
;System calls are kept at minimum, because are slow. The aproximate file size is determined by processing all file dir entries and summing up the record count instead of calling the system call for file size determination.
;Free space is determined by summing up file sizes on disk and substracting from maximum possible size (636KB). This allows showing up the ocupied space too, that the ROM doesn't list.
;Another way to determine space would be to make the system call to get disk the allocation bitmap, but that bitmap is in "phantom RAM" (IF1 paged RAM) so it's more convoluted to read and process it (count set bits).
;Would be probably faster to process the disk directory by reading the sectors and parsing manually, but that requires more code, and one objective was to have small and clear code. So system calls are used for Find First/Next.
;Mathematical operations like multiplication and division are performed using bit shifts, since involve numbers that are power of 2. Again this is for having simple and small code.
;Printing the text uses the BASIC ROM routine, that supports embedded color codes. The IF1 print routine doesn't support that. Direct screen output would be another way, but requires more code. Graphical output (64 columns) was excluded for the same reason.
;ROM printing routing has an issue with line 21 (out of 0-23), so a trick is used to avoid scrolling: channel 0 is used for the stats printing, then lines 0-21 are printed on channel 2, also poking a variable to prevent scrolling.
;The disk drive being displayed is the current drive, so the program should work as expected when executed from drive B:, as it doesn't hard code A:. A: is assumed when there's no current drive (like when loading from tape).
;What was used to develop this program: 
; - SjASMPlus v1.18.2 cross-assembler
; - Crimson Editor for editing, launching assembler, deploying in emulator
; - HC 2000 Emulator for Sinclair Spectrum +3 by Rares Atodiresei, for using the Spectaculator emulator with HC-2000 emulation support
; - Spectaculator emulator, for using the debugger and it's other top quality features
; - Fuse emulator, version from Alex Badea, with HC-2000 emulation support, for double testing
; - HCDisk2 by myself, for creating/updating disk images for HC in DSK format.
;
;Motivation? 
; - I wanted to refresh my Z80 assembly language
; - I wanted to create an usefull tool for HC computers, with features that don't exist yet
; - I wanted to publish the code, in case it's usefull in understanding how HC computers disk system works
;I realise some people may find it useless, but it's still a good exercise for myself and others.
;
;How it works:
;1. Reads disk catalog and saves a line in a table for each file, with info from directory entry 0: file name, RC count.
;2. Reads disk catalog again, to read the total record count for each file. This second pass is required because some files may have dir entry 1 show up before dir entry 0.
;3. Calculates disk space used by files, based on cache table record count, rounding up to 2048 (block size).
;4. Displays total used space on disk, file count, disk free space, listing page 1/2/3.
;5. Displays file list and file size in bytes, rounded up at 128 (CPM style). File attributes are shown in color, as noted on screen: red=read only, magenta=system (hidden from CAT), yellow=read only + system.

				DEVICE ZXSPECTRUM48

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Main program ;;;;;;;;;;;;;;;;;;;;;;;;;;								
	ORG START_ADDR
	
start:
	;install error handler
	ld		hl, (VAR_ERRSP)
	push	hl
	ld		hl, ErrorHandler
	push	hl
	ld		(VAR_ERRSP), sp	

	;Init IF1, disk
	call Init	

ReadDiskAgain:	
	;First read of catalog, to get file list	
	call ReadCatalog1				
	;Second read of catalog, to get file size
	call ReadCatalog2	
	;Calculate space used by files on disk
	call GetDiskUsedSpace	
	;Display list of files	
	call DisplayFiles	
	
	call ReadCharLoop
	
	;restore default error handler
	pop		hl
	pop		hl
	ld		(VAR_ERRSP), hl

	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Char routines ;;;;;;;;;;;;;;;;;;;;;;;;;


;Return read char in A
ReadChar:
	rst 08
	DEFB 27
	ret

;Print a string
;HL=str. addr.
;B=len
PrintStr:		
	ld a, (hl)
	push hl
	push bc
		rst $10				;Print using ROM routine, since it supports color output. The IF1 print routine doesn't.
	pop bc
	pop hl
	inc hl
	djnz PrintStr
	ret
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;	
SetFastKeys:
	ld		hl, VAR_REPDEL
	ld		de, (1 << 8) | 15
	ld		(hl), de
	ret	
	
;Compare string at HL with the one at DE, max length B
;IN: HL, DE = addr. of strings to compare, B = max. length of strings to compare
;OUT: z flag, set = match, reset = mismatch
StrCmp:
	push hl
	push de
Compare:
		ld a, (de)
		cp (hl)
		jr nz, MisMatch
		inc hl
		inc de
		djnz Compare
MisMatch:
	pop de
	pop hl
	ret	

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;	

Init:
;These 2 calls are not needed when this program is launched from disk, as it will display the current disk.
;If loaded from tape, it won't work without the 2 calls, since they are needed for DOS initialisation and selecting A: or B:.	
	call InitVars	
	call InitDos
	
	;Select the current drive to work with instead of hardcoding A:.
	call GetCurrentDrive	
	cp $FF							;$FF = no current drive, force A:
	jr  z, CurrentDriveNone		
	inc  a							;translate CP/M drive to BASIC drive: 0 -> 1, 1 -> 2
	jr  SelectDriveInit
CurrentDriveNone:	
	ld  a, DRIVE_A
SelectDriveInit:	
	call SelectDrive	
	
	;set border and paper to blue
	ld  a, CLR_BLUE
	out ($FE), a
	ld a, (CLR_BLUE << 3) | CLR_WHITE
	ld (VAR_BORDCR), a
	ld (VAR_ATTR), a
			
	;CLS
	ld  a, 2
	call ROM_OPEN_SCR_CLR		
	
	ld  a, 0
	call ROM_OPEN_SCR
	ld  hl, MsgIntro
	ld  b, MsgIntroEnd - MsgIntro
	call PrintStr
	
	call SetFastKeys
		
	ret
	
	
ErrorHandler:
	pop		hl
	ld		(VAR_ERRSP), hl
	
	ld		a, 2
	call	ROM_OPEN_SCR_CLR
	
	ld		a, 0
	call	ROM_OPEN_SCR
	
	ld		a, (VAR_ERRNR)
	push	af
	ld		l, a
	ld		h, 0
	ld		de, MsgErrCode
	call	N2ASCII3		

	ld		hl, MsgError
	ld		b, MsgErrorEnd - MsgError
	call	PrintStr
		
	pop		af	
	push	af
	call	GetErrMsg		
	ld		hl, Cache		
	call	PrintStr			
	
	;On disk error, select A:, in case drive B: was empty when selected.
	pop		af
	cp		$10
	jr		nz, DontSelectA
	ld		a, DRIVE_A
	call	SelectDrive

DontSelectA:				
	call	ReadChar	
	jp		start
	
	
;IN DE = message destination
GetErrMsg:
	inc		a
	ex		af, af'

	ld		hl, IF1Paged			;page-in IF1
	ld		(VAR_HD11), hl
	rst		8
	defb	50
	ret								;return after accesing IF1

IF1Paged:
	ld		hl, ERRMSG
	ex		af, af'
	or		a
	jr		z, SaveMsg

	ld		b, 0
SearchMsgEnd:
	bit		7, (hl)
	inc		hl
	jr		z, SearchMsgEnd

	inc		b
	cp		b
	jr		nz, SearchMsgEnd

SaveMsg:	
	ld		de, Cache
	ld		b, 0
CopyMsg:
	ld		a, (hl)	
	ld		(de), a
	inc		hl
	inc		de
	inc		b
	bit		7, a
	jr		z, CopyMsg
	ex		de, hl
	dec		hl
	res		7, (hl)
	ret			
	
	
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Disk routines ;;;;;;;;;;;;;;;;;;;;;;;;;
	
;Insert IF1 variables
InitVars:
	rst 08
	DEFB 49
	ret

;Create a disk channel for BDOS access (does not open the file)
;IN: HL=name addr, B=drive, C=name len
;OUT: IX=FCB
CreateChannel:
	ld (VAR_FSTR1), hl
	ld h,0
	ld l,b
	ld (VAR_DSTR1), hl
	ld l,c
	ld (VAR_NSTR1), hl
	rst 08
	DEFB 55
	ld bc, CH_FCB			;adjust to get cp/m fcb
	add ix, bc
	ret


;Destroy a BDOS channel
;IN: IX=FCB
DestroyChannel:	
	ld bc, -CH_FCB			;adjust to get the basic channel
	add ix, bc
	rst 08
	DEFB 56	
	ret


;Generic BDOS call
;IX=arg, A=function
BDOS:
	ld (VAR_HD11), ix
	ld (VAR_COPIES), a
	rst 08
	DEFB 57
	ret
	
InitDos:
	ld	a, 0
	jr	BDOS	

;IN A=selected drive	
SelectDrive:		
	ld  (DRIVE_SELECTED), a
	dec a		;CPM drive is 0=A or 1=B. For BASIC is 1=A, 2=B, 0=current drive. So we must convert it for the CPM call, otherwise the BDOS function crashes.
	ld  ixh, 0
	ld	ixl, a	;0=A, 1=B
	ld	a, 1	;1=Select disk	
	jr	BDOS		
	ret

;Returns current disk in A: 0=A:, 1=B:, $FF=no current drive
GetCurrentDrive:	
	ld a, 12
	jr BDOS
	
;FindFirst
;IX=fcb
FindFirst:
	ld a, 4
	jr BDOS


;FindNext
;IX=fcb
FindNext:
	ld a, 5
	jr BDOS
	

;Set DMA address for BDOS into the already alocated (and unused) 256 bytes channel buffer
;IX=fcb
SetDMA:
	ld bc, CH_DMA		;offset into alocated data area of the channel (256 bytes)
	push ix
		add ix, bc
		ld a, 13
		call BDOS
	pop ix
	ret
	
;Load a program from disk
;IN: HL = file name addr
LoadProgram:
	LD   (VAR_FSTR1), HL
	LD   H, 0
	LD   L, NAMELEN
	LD   (VAR_NSTR1), HL
	;LD	 A, (DRIVE_SELECTED)
	LD   L, DRIVE_CURRENT			;load from current drive
	LD   (VAR_DSTR1), HL
	LD   HL, LOAD_ADDR
	LD   (VAR_HD11), HL
	RST  8
	DEFB 50	
	ret								;ret to BASIC in case the program exits
	;Control is now given to the program being executed.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;				
	
;Sum up file size on disk for all files. It's easier than parsing the block bitmap in phantom RAM.
GetDiskUsedSpace:
	ld		hl, Cache	
	ld		a, (FileCnt)
	ld		b, a	
	
FileSizeLoop:	
	push	bc
		ld		bc, NAMELEN
		add		hl, bc				
	
		ld		c, (hl)
		inc		hl
		ld		b, (hl)
		inc		hl
		
		push	hl
			push	bc
			pop		hl		
			call	GetFileSizeOnDiskKB
			
			ld		bc, (UsedKB)
			add		hl, bc
			ld		(UsedKB), hl		
		pop		hl
	pop		bc
	djnz	FileSizeLoop	
	ret	
	

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;			
	
;IN HL=RC count
;OUT HL = File size on disk in KB
;(RC count * 128) / 2048 = RC count * 16 = block count. Block count * 2 = KB on disk
GetFileSizeOnDiskKB:
	xor a
	
	;/2
	srl	h
	rr	l
	rla
	;/4
	srl	h
	rr	l
	rla
	;/8
	srl	h
	rr	l
	rla
	;/16
	srl	h
	rr	l
	rla
	
	or  a	
	jr  z, NoPartialAU	
	inc	hl	
NoPartialAU:
	
	;block count * 2 = KB
	sla	l
	rl	h
	ret
		
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;			
	
;IN HL = RC count
DisplayFileLength:			
	;check if RC >= $200 RC, to display size in KB then, as it doesn't fit in 16 bits.		
	ld  a, 2
	sub h
	jr  c, BigFile
	
	;RC * 128 = size in bytes rounded at 128.	
	;h << 7	
	rrc h
	;l >> 1
	srl l	
	;save carry	in H
	rr h	
	;save L
	ld  a, l		
	ld  l, 0	
	;save bit 7 of L
	rl h
	rr l
	;save H + 7 bits of L
	or  h
	ld  h, a
		
	ld  de, FileLen
	call N2ASCII5
	
	ret

BigFile:		
	call GetFileSizeOnDiskKB

	ld  de, FileLen
	call N2ASCII3
	inc  de
	ld  a, 'K'
	ld  (de), a
	inc de
	ld  a, 'B'
	ld  (de), a	
			
	ret	
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;	
DisplayFiles:
	ld  a, '1'	
	ld  (ScrPageMsg), a	
	ld  (ScrPageMsgMax), a	
	
	ld a, (FileCnt)	
	or a
	jr  nz, NonEmptyDisk	
	call DisplayStats
	call ReadChar
	ret
	
NonEmptyDisk:		
	;detemine how many file list pages we have (1-3)
	ld hl, ScrPageMsgMax		
ScreenCntLoop:	
	sub MAX_FILES_SCR
	inc (hl)
	jr  nc, ScreenCntLoop					
	dec (hl)

DisplayFilesLoop:	
	xor a
	ld (TabChar), a
	
	call GetFileListForScreen
	ld  a, b
	ld  (FileCntScr), a
	call DisplayOneScreen
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;	
	
ReadCharLoop:
	call ReadChar	
	cp  KEY_ESC	
	ret z
	
	cp  '1'
	jr  z, SelectDriveA
	cp  '2'
	jr  z, SelectDriveB
	
	cp KEY_DOWN
	jr nz, CheckKeyUp	
	call CursorDown
	jr ReadCharLoop

CheckKeyUp:
	cp KEY_UP
	jr nz, CheckKeyRight
	call CursorUp
	jr ReadCharLoop
	
CheckKeyRight:	
	cp KEY_RIGHT
	jr nz, CheckKeyLeft
	call CursorRight
	jr ReadCharLoop
	
CheckKeyLeft:	
	cp KEY_LEFT
	jr  nz, CheckEnter
	call CursorLeft	
	jr  ReadCharLoop
	
CheckEnter:
	cp KEY_ENTER
	jr nz, ReadCharLoop			
		
	;Read current screen number.
	ld a, (ScrPageMsg)	
	sub '1'
	or  a
	jr  z, FirstPageIndex
	ld  b, a			
	xor a
PageAddLoop:	
	add MAX_FILES_SCR	
	djnz PageAddLoop
FirstPageIndex:			
	ld hl, SelFileIdxScr
	add (hl)
	ld  b, a
	call FindCacheByIndex
	
	pop de							;restore stack for this call
	;restore default error handler, if a game throws an error, the error handler might be overwritten already.
	/*
	ex  de, hl		
	pop		hl
	pop		hl
	ld		(VAR_ERRSP), hl
	ex  de, hl
	*/
	
	;Control is now given to the program being executed.	
	jp LoadProgram		
	
SelectDriveA:
	ld  a, DRIVE_A
	jr  SwitchDrive
SelectDriveB:
	ld  a, DRIVE_B
SwitchDrive:		
	call SelectDrive
	pop  hl							;restore stack for this call
	jp   ReadDiskAgain

NextScr:
	ld hl, ScrPageMsg
	ld a, (ScrPageMsgMax)
	cp (hl)
	ret z
	inc (hl)	
	jp DisplayFilesLoop	
	
PrevScr:	
	ld hl, ScrPageMsg	
	ld  a, '1'
	cp (hl)
	ret z
	dec (hl)	
	jp DisplayFilesLoop	
	
	
CursorDownOrRight:		
	ld a, (FileCntScr)
	ld b, a			
	ld a, (SelFileIdxScr)
	add c
	cp b		
	jr c, CursorDownValidSelection
	
	;Cursor moved outside screen, check if we need to move to next screen.
	ld  a, MAX_FILES_SCR
	cp  b
	jr  z, NextScr
	ret
	
CursorDownValidSelection:	
	;The selection is within the file list, draw it.
	ld (SelFileIdxScr), a
	push bc
	push af
		call DrawCursor
	pop af
	pop bc
	sub c
	call DrawCursor
	ret
	
	
CursorDown:	
	ld  c, 2
	jr  CursorDownOrRight
	
CursorRight:
	ld  c, 1
	jr  CursorDownOrRight
	
CursorUp:
	ld c, 2
	jr CursorUpOrLeft
	
CursorLeft:
	ld c, 1
	jr CursorUpOrLeft	

CursorUpOrLeft:
	ld a, (SelFileIdxScr)
	cp c
	jr c, PrevScr

	push bc	
	push af
		call DrawCursor
	pop af
	pop bc
	sub c
	ld (SelFileIdxScr), a
	call DrawCursor	
	ret
		
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;IN A = file index to highlite (0 - 43)
DrawCursor:
	ld c, a
	ld b, 0
	;*16
	sla c
	rl b
	sla c
	rl b
	sla c
	rl b
	sla c
	rl b
	
	ld hl, SCR_ATTR_ADDR
	add hl, bc
	
	ld b, SCR_COLUMNS/2
DrawCursorLoop:	
	ld a, (hl)
	;draw inverse	
	and %111
	ld  c, a	
	rl c
	rl c
	rl c
	ld a, (hl)
	and %111000
	rra
	rra
	rra
	or c
	ld  c, a
	ld a, (hl)
	;keep bright, flash
	and %11000000
	or c
	ld (hl), a
	inc hl
	djnz DrawCursorLoop
	
	ret	
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;	
;Determine the cache line to start with (in HL) and how many files to show (in B)
;page1 = files 1-44, page2 = files 45 - 88, page3 = 89 - 128
GetFileListForScreen:			
	ld  a, (FileCnt)
	ld  c, a
	ld  a, (ScrPageMsg)
	ld  e, a
	ld a, (ScrPageMsgMax)		
	cp '1'		
	jr  z, OneScreenMax
	cp '2'
	jr  z, TwoScreensMax
	cp '3'
	jr  z, ThreeScreensMax	
	
;determine file list offset for file list on screen and file count for
OneScreenMax:
	ld  b, 0	
	jr 	FindCacheLine
TwoScreensMax:		
	ld  a, e
	cp  '2'
	jr  z, Page2of2
Page1of2:	
	ld  b, 0					;start from first file for page 1
	ld  c, MAX_FILES_SCR		;display full screen of files, more to come
	jr  FindCacheLine
Page2of2:	
	ld  b, MAX_FILES_SCR		;skip first page of files for page 2
	ld  a, c					
	sub MAX_FILES_SCR
	ld  c, a					;get rest of files for page 2
	jr 	FindCacheLine
ThreeScreensMax:
	ld  a, e
	cp  '3'
	jr  z, Page3of3
	cp  '2'
	jr  z, Page2of3
Page1of3:
	ld  b, 0					;start from first file for page 1
	ld  c, MAX_FILES_SCR		;display full page of files, more to come	
	jr  FindCacheLine
Page2of3:
	ld  b, MAX_FILES_SCR		;skip first page of files for page 2
	ld  c, MAX_FILES_SCR		;display full page of files, more to come	
	jr  FindCacheLine
Page3of3:	
	ld  b, 2*MAX_FILES_SCR		;skip first 2 pages of files for page 3
	ld  a, c
	sub MAX_FILES_SCR
	sub MAX_FILES_SCR	
	ld  c, a					;get rest of files for page 2
	
FindCacheLine:	
	call FindCacheByIndex
	
	ld  b, c		
	ret	
	
;IN B=cache index to put in HL	
FindCacheByIndex:
	ld	de, CACHE_LN_SZ	
	ld 	hl, Cache	
	ld  a, b
	or  a
	ret z
FindCacheLineLoop:	
	add	hl, de
	djnz FindCacheLineLoop		
	ret
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;	
;Shows file lists for one screen, with cache from HL and file count from B
DisplayOneScreen:							
	push	bc		
	push	hl
		ld  a, 2
		call ROM_OPEN_SCR_CLR		
		;Display occupied space, file number, free space, page
		call DisplayStats						
	pop		hl
	pop		bc
	
	push 	bc
	push 	hl			
		;prevent scroll up, to be able to display on row 21
		xor a	
		ld  (VAR_SCROLL2), a
		
		ld (DisplayedBright), a
	
		call DisplayFilesInfo								
		
		;restore scroll, to prevent crash
		ld  hl, VAR_SCROLL2
		ld  (hl), 2
		
		xor a
		ld (SelFileIdxScr), a
		call DrawCursor
	pop	 hl
	pop  bc	
	
	ret

		
;Displays info for each file. A table already contains lines of: FileName, RC count
;IN HL=file cache line, B=file count
DisplayFilesInfo:		
	push hl
	ld  a, 2
	call ROM_OPEN_SCR
	pop	hl	
	
	;return if 0 files on disk
	ld a, b
	or a
	ret z
	
	;Use C as file index, for alternating brightness.
	ld  c, 1
DisplayLoop:	
	push bc		
	push hl	
		;set file name for display
		ld   de, FileName
		push de		
			ld	 bc, NAMELEN
			ldir 					
							
			ld  bc, (hl)
			ld  l, c
			ld  h, b	
			call DisplayFileLength			
		pop  ix
				
		call CheckAttributes								
		
		;fix invalid chars in name
		ld  b, NAMELEN			
		ld  hl, FileName
FileNameCopy:			
		ld  a, (hl)		
		and $7F									;clear bit 7; LOAD accepts bit 7 set or not set (char SCREEN$ or *)
		cp  ' '
		jr  nc, GoodChar
		ld  a, '?'				
GoodChar:				
		ld  (hl), a			
		inc  hl		
		djnz FileNameCopy										
					
		;display line						
		ld hl, DisplayedLine
		ld b, DisplayedLineEnd-DisplayedLine	;how many chars on one line
		call PrintStr		
		
		;set tab every 2 entries
		ld a, (TabChar)
		xor SCR_COLUMNS/2		
		ld (TabChar), a				
	pop hl
	ld  bc, CACHE_LN_SZ
	add hl, bc
	pop bc		
	
	;set alternating bright every 2 entries
	ld  a, c	
	and 2
	rra
	ld (DisplayedBright), a	
	inc c
	djnz DisplayLoop
		
	ret	


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;		
		
;Checks the attributes and reset the bits, saving result as color attribute
;IX=file name
CheckAttributes:
	ld  a, CLR_NAME
	bit 7, (ix+ATTR_RO_POS)		
	jr  z, NotRO		
	res 7, (ix+ATTR_RO_POS)	
	ld  a, CLR_RO
NotRO:
	bit 7, (ix+ATTR_SYS_POS)	
	jr  z, NotSys
	res 7, (ix+ATTR_SYS_POS)			
	cp  CLR_RO
	jr  z, BothAttr
	ld  a, CLR_SYS
	jr  NotSys	
BothAttr:
	ld  a, CLR_RO_SYS	
NotSys:		
	ld (FileNameClr), a
	ret


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;			

;Read directory and create a table (name - 11B, RC count - 2B)
ReadCatalog1:	
	xor a
	ld l, a
	ld h, a
	ld (UsedKB), hl					;reset used blocks		
	ld (FileCnt), a					;reset file counter							
	ld  a, MAX_DIR_ENT
	ld (FreeCatalog), a

	ld hl, FileMask
	ld a, (DRIVE_SELECTED)
	ld b, a							;drive
	ld c, NAMELEN					;name len	
	call CreateChannel
	call SetDMA

	ld	a, 0						;request first extension
	ld (ix + FCB_EX_IDX), a	

	call FindFirst
	ld de, Cache
		
CatNext:		
	inc a
	jr z, CatEnd			;return if A=FFh	
	dec a								
		
	push ix
		ld bc, CH_DMA
		add ix, bc
				
		;A is the index for the 32 byte dir. entry in DMA buffer
		rla
		rla
		rla
		rla
		rla
		ld b, 0			
		ld c, a
		add ix, bc						;hl=file name -1=FCB			
																
		;put name in cache		
		push ix
		pop hl
		inc hl						;HL = file name
		ld  bc, NAMELEN
		ldir
		
		;skip EX, S1, S2
		inc hl
		inc hl
		inc hl
		;save RC count for first extension
		ldi		
		xor a
		ld (de), a
		inc de
	pop  ix	
	
	ld a, (FileCnt)
	inc a
	ld (FileCnt), a
	
	;find next file
	push de
		call FindNext
	pop de		
		
	jr CatNext	
CatEnd:			
	
	call DestroyChannel
	ret
	

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;Will ignore extensions with index 0, will add up RC count for subsequent extensions.
ReadCatalog2:	
	ld hl, FileMask
	ld a, (DRIVE_SELECTED)
	ld b, a							;drive
	ld c, NAMELEN					;name len	
	call CreateChannel
	call SetDMA

	ld	a, '?'						;request all extensions
	ld (ix + FCB_EX_IDX), a	

	call FindFirst	
		
CatNext2:		
	inc a
	jr z, CatEnd2			;return if A=FFh	
	dec a								
	
	ld hl, FreeCatalog
	dec (hl)
		
	push ix
		ld bc, CH_DMA
		add ix, bc
				
		;A is the index for the 32 byte dir. entry in DMA buffer
		rla
		rla
		rla
		rla
		rla
		ld b, 0			
		ld c, a
		add ix, bc						;hl=file name -1=FCB				
														
		;now ignore entries with index 0, as these are already processed	
		ld  a, (ix + FCB_EX_IDX)
		or  a
		jr  z, Cat2Index0
		
		;find cache for this file
		push ix
		pop  hl
		inc  hl
		call FindCacheByName
		
		ex  de, hl
		ld  bc, NAMELEN
		add hl, bc
		
		;add RC count in cache		
		ld  c, (hl)
		inc hl
		ld  b, (hl)		
		dec hl
		ex  de, hl
		ld  l, (ix + FCB_RC)
		ld  h, 0
		add hl, bc
		ex  de, hl
		ld  (hl), e
		inc hl
		ld  (hl), d		
Cat2Index0:		
	pop  ix	
		
	call FindNext	
		
	jr CatNext2	
CatEnd2:			
	
	call DestroyChannel
	ret	

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;		
;IN HL = name address
;OUT DE = file row in cache
FindCacheByName:
	ld  de, Cache	
	
FindCacheLoop:	
	push hl
	push de	
		ld  b, NAMELEN
		call StrCmp			
	pop  de
	pop  hl
	ret z
	
	;skip RC count in cache
	ex  de, hl
	ld  bc, CACHE_LN_SZ
	add hl, bc
	ex  de, hl
	jr  FindCacheLoop
	

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;		

;Displays free space
DisplayStats:		
	ld   hl, (UsedKB)		
	push hl		
		ld de, UsedSpaceAsc
		call N2ASCII3
	pop  bc
		
	ld  hl, (MAX_FREE_AU_CNT * AU_SZ)/1024
	sub hl, bc	
	ld de, FreeSpaceAsc
	call N2ASCII3			
	
	ld a, (FileCnt)
	ld h, 0
	ld l, a
	ld de, FileCntMsg
	call N2ASCII3			
	
	ld  a, (DRIVE_SELECTED)		
	add 'A'-1
	ld  (MsgDrive), a		
	
	ld a, (FreeCatalog)	
	ld l, a	
	ld h, 0	
	ld de, UsedCatMsg
	call N2ASCII3			

PrintStats:			
	ld	a, 0
	call ROM_OPEN_SCR
	ld hl, FreeSpaceMsg
	ld b, FreeSpaceMsgEnd - FreeSpaceMsg	
	call PrintStr
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Number routines ;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;Converts the 3 digit number in HL to ASCII at DE
N2ASCII3:
	push de
		call N2ASCII_DEC3
	pop de
	ld  bc, $0200
	jr StrippLoop

;Converts the 5 digit number in HL to ASCII
N2ASCII5:
	push de
		call N2ASCII_DEC
	pop de

StrippLeading0:
	ld bc, $0400
	;ld c, 0
StrippLoop:
	ld a, (de)
	cp '0'
	jr nz, MarkNon0
	ld a, c
	;cp 0
	or a
	jr nz, NextChar
	ld a, ' '
	ld (de), a
	jr NextChar
MarkNon0:
	inc c
NextChar:
	inc de
	djnz StrippLoop
	ret


;The folowing routine was inspired from: Milos "baze" Bazelides, baze@stonline.sk
;http://map.tni.nl/sources/external/z80bits.html

;Converts the number in HL to ASCII in decimal string at DE
N2ASCII_DEC:
	ld bc, -10000
	call DigitLoop
	ld bc, -1000
	call DigitLoop
N2ASCII_DEC3:	
	ld bc, -100
	call DigitLoop
	ld bc, -10
	call DigitLoop
	ld bc, -1

DigitLoop:
	ld	a, '0' - 1
DivNrLoop:
	inc	a			;increase reminder
	add	hl, bc		;substract divizor
	jr	c, DivNrLoop	;still dividing?
	sbc	hl, bc		;nope, restore

	ld (de), a
	inc de
	ret


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Allocated Data ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

FreeSpaceMsg:	
				DEFB	CLR_CODE_INVERSE, 1
				DEFB	CLR_CODE_BRIGHT, 1
				DEFB	CLR_CODE_PAPER, CLR_BLUE
				DEFB	CLR_CODE_INK, CLR_YELLOW				
ScrPageMsg		DEFB	"1/"
ScrPageMsgMax	DEFB	"1"
				DEFB	CLR_CODE_INK, CLR_NAME, "FILENAME"
				DEFB	CLR_CODE_INK, CLR_LEN, "LEN B"
				DEFB    CLR_CODE_INK, CLR_RO, "+R/O"								
				DEFB 	CLR_CODE_INK, CLR_SYS, "+SYS"
				DEFB 	CLR_CODE_INK, CLR_RO_SYS, "+R/O+SYS"				
											
				DEFB	CLR_CODE_INK, CLR_CYAN
MsgDrive		DEFB	"A: "
				DEFB	CLR_CODE_INK, CLR_RED
UsedSpaceAsc	DEFM	"   KB"				
FileCntMsg		DEFM    "   FILES"
				DEFB	CLR_CODE_INK, CLR_GREEN
FreeSpaceAsc	DEFM	"   KB"
UsedCatMsg		DEFM 	"   DIR FREE"				
FreeSpaceMsgEnd:


DisplayedLine:
				DEFB	CLR_CODE_TAB						;tab
TabChar			DEFB	0, 0
				DEFB	CLR_CODE_PAPER, CLR_BLUE
				DEFM	CLR_CODE_BRIGHT
DisplayedBright	DEFB	0				;bright is alternating
				DEFB	CLR_CODE_INK
FileNameClr		DEFB	CLR_NAME
FileName		DEFM	"???????????"
				DEFB	CLR_CODE_INK, CLR_LEN
FileLen			DEFB	"     "
DisplayedLineEnd:

MsgError		DEFB	CLR_CODE_PAPER, CLR_RED, CLR_CODE_BRIGHT, 1
				DEFM	"Error "
MsgErrCode		DEFM	"   : "
MsgErrorEnd

MsgIntro		DEFM	CLR_CODE_BRIGHT, 1 ,CLR_CODE_INK, CLR_WHITE, CLR_CODE_PAPER, CLR_RED
				DEFM	"CURSOR+CR=RUN;1/2=A:/B:;ESC=EXIT"
				DEFM	127, "2022 GEORGE.CHIRTOACA@GMAIL.COM"
MsgIntroEnd:

;the search mask
FileMask		DEFM	"???????????"
END

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Unalocated Variables ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

DRIVE_SELECTED	EQU		FileMask + NAMELEN
FileCnt			EQU		DRIVE_SELECTED + 1		;file index for display
UsedKB			EQU		FileCnt + 1
FreeCatalog		EQU		UsedKB + 2
SelFileIdxScr	EQU		FreeCatalog + 1
FileCntScr		EQU		SelFileIdxScr + 1
Cache			EQU		FileCntScr + 1				;here goes the cache table

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Constants ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

START_ADDR		EQU	32768		;Start address

;System variables for disk
VAR_DSTR1		EQU	$5CD6		;drive
VAR_FSTR1		EQU	$5CDC		;file name
VAR_NSTR1		EQU	$5CDA		;name length
VAR_HD11		EQU	$5CED		;BDOS argument
VAR_COPIES		EQU	$5CEF		;BDOS function
VAR_IOBORD		EQU	23750		;IO border
VAR_ATTR		EQU 23693		;color attribute
VAR_BORDCR		EQU 23624

VAR_SCROLL		EQU	23692
VAR_SCROLL2		EQU	23659
VAR_BORDER		EQU	$5C47
VAR_ERRSP		EQU $5C3D
VAR_ERRNR		EQU $5C3A
VAR_REPDEL		EQU	23561

;IF1
LOAD_ADDR		EQU	2625		;address of the load procedure in IF1 ROM
ERRMSG			EQU	$0260

DRIVE_CURRENT	EQU 0
DRIVE_A			EQU	1
DRIVE_B			EQU	2

;File name stuff
NAMELEN			EQU	11			;name length
ATTR_RO_POS		EQU	8			;read-only attribute position in name
ATTR_SYS_POS	EQU	9			;system attribute position in name

;Disk geometry stuff
SPT				EQU	16			;sectors per track
SECT_SZ			EQU	256			;sector size in bytes
TRACK_CNT		EQU	80			;track count
HEAD_CNT		EQU	2			;disk face count
AU_SZ			EQU	2048		;allocation unit size in bytes
DIR_ENT_SZ		EQU	32			;directory entry size
DIR_TRK_CNT		EQU	1			;tracks rezerved for directory
SPAL			EQU	(AU_SZ/SECT_SZ);sectors per allocation unit
MAX_DIR_ENT		EQU	(SPT * DIR_TRK_CNT * SECT_SZ / DIR_ENT_SZ);maximum directory entries
MAX_AU_CNT		EQU	(TRACK_CNT * HEAD_CNT * SPT * SECT_SZ)/AU_SZ
MAX_FREE_AU_CNT	EQU	((TRACK_CNT * HEAD_CNT - DIR_TRK_CNT) * SPT * SECT_SZ)/AU_SZ ;max free allocation units
REC_SZ			EQU 128			;cp/m record size
FINISH_CHR		EQU $1A			;file terminator char

;File header offsets
HDR_TYPE		EQU	0
HDR_LEN			EQU 1
HDR_ADDR		EQU 3
HDR_VAR			EQU	5
HDR_LINE		EQU 7
HDR_SIZE		EQU 9

;Disk cache table structure
CACHE_NAME		EQU 0
CACHE_RC_CNT	EQU NAMELEN
CACHE_LN_SZ		EQU NAMELEN +2

;BASIC disk channel structure
CH_RW_FLAG		EQU 11
CH_FCB			EQU	12
CH_DATA			EQU	50
CH_DMA			EQU CH_DATA - CH_FCB	;offset of DMA from start of FCB

;Extension structure (directory entry)
EXT_DEL_FLAG	EQU	0
EXT_NAME		EQU 1
EXT_IDX			EQU 12
EXT_S1			EQU 13
EXT_S2			EQU 14
EXT_RC			EQU	15
EXT_AU0			EQU	16
EXT_AU1			EQU	18
EXT_AU2			EQU	20
EXT_AU3			EQU	22
EXT_AU4			EQU	24
EXT_AU5			EQU	26
EXT_AU6			EQU	28
EXT_AU7			EQU	30
EXT_AU_CNT		EQU 8

;FCB structure
FCB_DRIVE		EQU 0			;0 is current drive
FCB_NAME		EQU EXT_NAME
FCB_EX_IDX		EQU EXT_IDX
FCB_S1			EQU EXT_S1
FCB_S2			EQU EXT_S2
FCB_RC			EQU	EXT_RC
FCB_AU			EQU	EXT_AU0
FCB_CR			EQU	32
FCB_R0			EQU 33
FCB_R1			EQU 34
FCB_R2			EQU 35

ROM_OPEN_SCR	EQU	$1601
ROM_OPEN_SCR_CLR	EQU	$0DAF
ROM_PRINT		EQU $203C		;DE = string, BC = len

CLR_CODE_INK	EQU 16
CLR_CODE_PAPER	EQU 17
CLR_CODE_BRIGHT EQU	19
CLR_CODE_INVERSE EQU	20
CLR_CODE_TAB	EQU 23

CLR_BLACK		EQU	0
CLR_BLUE		EQU	1
CLR_RED			EQU	2
CLR_MAGENTA		EQU	3
CLR_GREEN		EQU	4
CLR_CYAN		EQU	5
CLR_YELLOW		EQU	6
CLR_WHITE		EQU	7

CLR_NAME		EQU CLR_CYAN
CLR_RO			EQU	CLR_RED
CLR_SYS			EQU	CLR_MAGENTA
CLR_RO_SYS		EQU	CLR_GREEN
CLR_LEN			EQU	CLR_YELLOW

SCR_ATTR_ADDR	EQU 22528
SCR_ATTR_LEN	EQU	768
SCR_COLUMNS		EQU	32
SCR_LINES		EQU 24

;key codes
KEY_ESC			EQU	7
KEY_LEFT		EQU	8
KEY_RIGHT		EQU	9
KEY_DOWN		EQU	10
KEY_UP			EQU	11
KEY_ENTER		EQU	13
KEY_CTRL		EQU	14

MAX_FILES_SCR	EQU	44


				EMPTYTAP "cat.tap"
				savetap "cat.tap", CODE, "run", start, END-start
				savebin "cat.bin", start, END-start				
