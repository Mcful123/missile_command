# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'
	EXPLOSION = 64

	# ascii space to erase things
	SPACE = 32

	# ascii '+' for crosshair
	xhair = 43

# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:	
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
		# setup stackframe
		PUSHL %EBP
		MOVL %ESP, %EBP
		
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		
		# self-explanatory calls
		CALL update_missiles
		CALL mp1_redraw_cities
		CALL mp1_redraw_xhairs
		
mp1_rtc_tasklet_DONE:
		# stack teardown
		POPL %EDI
		POPL %ESI
		POPL %EBX

		leave
		ret

# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
		# get function argument
		MOVL 8(%ESP), %EDX
		CMPL $0, %EDX # range checking
		JL invalid_cmd
		CMPL $4, %EDX # range checking
		JG invalid_cmd

		JMP *jump_table(, %EDX, 4) # jump commands
		invalid_cmd:
		MOVL $-1, %EAX
		ret


# ----------------- Functions private to this file -------------------
#
#	update missiles traverses the missile list and updates status and/or positions
#	input: nothing
#	return: nothing
#
update_missiles:
		# setup stackframe
		PUSHL %EBP
		MOVL %ESP, %EBP
		
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		
		MOVL $0, %EDI # clear EDI because it is used as missile explode status tracker		
		MOVL mp1_missile_list, %EBX # set missile list head to EBX

	walk_down_missile_list:	 
		CMPL $0, %EBX # check if end of list
		JE update_missiles_DONE
		
		CMPL $0, EXPLODED(%EBX)
		JNE call_missile_explode	

		# if_ not exploded, erase missile at current position and update position 
		MOVL Y(%EBX), %EAX
		SARL $16, %EAX # only want the upper 16 bits
		IMULL $80, %EAX
		MOVL X(%EBX), %EDX
		SARL $16, %EDX # only want the upper 16 bits
		ADDL %EDX, %EAX
		IMULL $2, %EAX # EAX = 2*(Y*80 + X)
		MOVB $SPACE, %CL 
		CALL mp1_poke
		
		# updating positions of x and y 
		MOVL VX(%EBX), %ECX
		ADDL %ECX, X(%EBX)
		MOVL VY(%EBX), %ECX
		ADDL %ECX, Y(%EBX)
		
		# check if_ position out of bounds
		# x range: 0-79; y range: 0-24
		MOVL X(%EBX), %EDX
		SARL $16, %EDX # EDX holds x screen position
		CMPL $0, %EDX 
		JL missile_out_of_bound 
		CMPL $79, %EDX
		JG missile_out_of_bound
		MOVL Y(%EBX), %EDX # EDX holds y screen position
		SARL $16, %EDX
		CMPL $0, %EDX
		JL missile_out_of_bound
		CMPL $24, %EDX
		JG missile_out_of_bound
		
		# check if_ missile reached X destination
		MOVL DEST_X(%EBX), %ESI
		MOVL X(%EBX), %EDX
		SARL $16, %EDX
		CMPL %ESI, %EDX
		JNE redraw_missile # not reached X position means missile should continue 

		# check if_ missile reached y destination
		MOVL DEST_Y(%EBX), %ESI
		MOVL Y(%EBX), %EDX
		SARL $16, %EDX
		CMPL %ESI, %EDX
		JE call_missile_explode
		
	redraw_missile:
		MOVL Y(%EBX), %EAX
		SARL $16, %EAX # # only want the upper 16 bits
		IMULL $80, %EAX
		MOVL X(%EBX), %EDX
		SARL $16, %EDX # # only want the upper 16 bits
		ADDL %EDX, %EAX
		IMULL $2, %EAX # # EAX = 2*(Y*80 + X)
		MOVB C(%EBX), %CL 
		CALL mp1_poke
		MOVL NEXT(%EBX), %EBX
		JMP walk_down_missile_list # go back to top of loop

	missile_out_of_bound:
		MOVL NEXT(%EBX), %ECX # save next missile pointer
		PUSHL %ECX
		CALL mp1_missile_remove
		POPL %ECX
		MOVL %ECX, %EBX # load back next missile pointer
		JMP walk_down_missile_list	# go back to top of loop	
		
	call_missile_explode: 	
		# caller saved registers
		PUSHL %EAX
		PUSHL %ECX
		PUSHL %EDX
		PUSHL %EBX # push missile pointer onto stack
		CALL missile_explode # make the call
		ADDL %EAX, %EDI
		ADDL $4, %ESP 
		POPL %EDX
		POPL %ECX
		POPL %EAX
		
		SUBL $1, EXPLODED(%EBX) # decrement exploded counter
		MOVL EXPLODED(%EBX), %EAX
		CMPL $0, %EAX # check if missile is finished exploding
		JE finished_exploding
		
		# bound checking seems redundant but without it, kernel panic occurs
	draw_explosion:
		MOVL Y(%EBX), %EAX
		SARL $16, %EAX  # only want the upper 16 bits
		CMPL $0, %EAX  # bound check if explosion is being drawn out of bounds
		JL draw_explosion_DONE 
		CMPL $24, %EAX
		JG draw_explosion_DONE
		IMULL $80, %EAX
		MOVL X(%EBX), %EDX
		SARL $16, %EDX # only want the upper 16 bits
		CMPL $0, %EDX
		JL draw_explosion_DONE
		CMPL $79, %EDX
		JG draw_explosion_DONE
		ADDL %EDX, %EAX
		IMULL $2, %EAX # EAX holds
		MOVB $EXPLOSION, %CL 
		CALL mp1_poke
		
	draw_explosion_DONE:
		MOVL NEXT(%EBX), %EBX
		JMP walk_down_missile_list
	finished_exploding:
		MOVL Y(%EBX), %EAX
		SARL $16, %EAX # only want the upper 16 bits
		IMULL $80, %EAX
		MOVL X(%EBX), %EDX
		SARL $16, %EDX # only want the upper 16 bits
		ADDL %EDX, %EAX
		IMULL $2, %EAX # EAX = 2*(Y*80 + X)
		MOVB $SPACE, %CL 
		CALL mp1_poke
		MOVL NEXT(%EBX), %ECX	
		PUSHL %ECX
		CALL mp1_missile_remove
		POPL %ECX
		MOVL %ECX, %EBX
		JMP walk_down_missile_list

update_missiles_DONE:
		# check if missile explode ever returned a non-zero
		CMPL $0, %EDI
		JE update_missile_stack_teardown
		# if_ it ever returned zero, call mp1_notify_user
		PUSHL %EAX
		PUSHL %ECX
		PUSHL %EDX
		CALL mp1_notify_user
		POPL %EDX
		POPL %ECX
		POPL %EAX
	update_missile_stack_teardown:
		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret
#
#
# mp1_missile_remove function removes the missile at register EBX from the missile list
# returns nothing
#
mp1_missile_remove:
		# setup stackframe
		PUSHL %EBP
		MOVL %ESP, %EBP
		
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		
		MOVL NEXT(%EBX), %EDI # save current NEXT pointer

		# check if removing missile list head
		MOVL mp1_missile_list, %ESI
		CMPL %ESI, %EBX
		JE case_head
		
		# if_ missile is not head, change previous missile NEXT pointer to the current NEXT
	loop_top:
		MOVL NEXT(%ESI), %ECX
		CMPL %ECX, %EBX
		JE update_prev_next	
		MOVL NEXT(%ESI), %ESI
		JMP loop_top
		
	case_head:
		MOVL %EDI, mp1_missile_list
		JMP call_mp1_free

	update_prev_next:
		MOVL %EDI, NEXT(%ESI) 

	call_mp1_free:
		# save caller save registers	
		PUSHL %EAX
		PUSHL %ECX
		PUSHL %EDX
		PUSHL %EBX # push argument onto stack
		CALL mp1_free # make the call
		# stack teardown pops
		POPL %EBX 
		POPL %EDX
		POPL %ECX
		POPL %EAX
		
mp1_missile_remove_DONE:
		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret

#
#
# redrawing cities function 
# input: nothing
# return: nothing
mp1_redraw_cities:
		# setup stackframe
		PUSHL %EBP
		MOVL %ESP, %EBP
		
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI

		# drawing first city
		MOVL base_alive, %EBX
		MOVL $18, %ESI # 18 is the starting position of first base
		ANDL $0x000000FF, %EBX
		CALL draw_city

		# drawing second city
		MOVL base_alive, %EBX
		MOVL $38, %ESI # 38 is the starting position of second base
		ANDL $0x0000FF00, %EBX
		CALL draw_city
		
		# drawing third city
		MOVL base_alive, %EBX
		MOVL $58, %ESI # 58 is the starting position of third base
		ANDL $0x00FF0000, %EBX
		CALL draw_city

		JMP mp1_redraw_cities_DONE

	# input: %EBX holds status dead or alive
	#		 %ESI holds starting position of city
	# 		 %EDI holds 5 for iteration
	draw_city:
		MOVL $5, %EDI
		CMPL $0, %EBX
		JE load_dead_city
		LEAL base_pic, %EDX
		MOVL $0, %EBX # EBX now points to the base character
		JMP draw_city_loop
	load_dead_city:
		LEAL dead_base_pic, %EDX 
		MOVL $0, %EBX # same as above
	draw_city_loop:
		MOVL $24, %EAX # drawing cities on row 24
		IMULL $80, %EAX
		ADDL %ESI, %EAX
		IMULL $2, %EAX # EAX now holds position for mp1_poke
		MOVB (%EBX, %EDX), %CL
		PUSHL %EDX
		CALL mp1_poke
		POPL %EDX
		ADDL $1, %ESI
		ADDL $1, %EBX
		CMPL %EBX, %EDI
		JNE draw_city_loop
		ret

mp1_redraw_cities_DONE:
		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret
#
# 
# redraw_xhairs just draws the crosshair at position crosshairs_x and crosshairs_y
# input: nothing 
# return: nothing
mp1_redraw_xhairs:
		# setup stackframe
		PUSHL %EBP
		MOVL %ESP, %EBP
		
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI

		MOVL crosshairs_y, %EAX
		IMULL $80, %EAX
		ADDL crosshairs_x, %EAX
		IMULL $2, %EAX

		MOVB $xhair, %Cl 
		CALL mp1_poke

mp1_redraw_xhairs_DONE: # stack teardown 
		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret

# ******* 	CORE FUNCTIONS  ********
#
# mp1_ioctl functions
# startgame initializes missile list head pointer, score, crosshair position, and sets all bases to alive
# input nothing
# output return nothing
mp1_ioctl_startgame:
		# setup stackframe
		PUSHL %EBP
		MOVL %ESP, %EBP
		
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI

		MOVL $0, mp1_missile_list # initialize missile list to empty
		MOVL $0, mp1_score # initialize score to 0
		MOVL $40, crosshairs_x
		MOVL $12, crosshairs_y # set crosshair in the middle when starting
		MOVL $0x00FFFFFF, base_alive # all 3 cities are alive

		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret
#
#
# adds a new missile to the head of the list. Missile parameters copied from user
# input: address of new missile
# return: 0 for success, -1 for fail
mp1_ioctl_addmissile:
		# setup stackframe
		PUSHL %EBP
		MOVL %ESP, %EBP
		
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		
		MOVL 8(%EBP), %EBX # put user_missile argument into EBX
		PUSHL $33 # push argument 'size' (size of struct) for malloc
		CALL mp1_malloc
		ADDL $4, %ESP
		MOVL %EAX, %ESI # esi has address of new missile node
		CMPL $0, %EAX
		JE malloc_null
		PUSHL $33 # calling copy from user with arguments then pops arguments at the end
		PUSHL %EBX
		PUSHL %ESI
		CALL mp1_copy_from_user
		ADDL $12, %ESP # pop arguments off stack
		
		CMPL $0, %EAX
		JNE invalid_copy 

		MOVL mp1_missile_list, %EDI
		MOVL %EDI, NEXT(%ESI)
		MOVL %ESI, mp1_missile_list
		JMP mp1_ioctl_addmissile_DONE

	invalid_copy: # free badly allocated memory 
		PUSHL %ESI
		CALL mp1_free
		ADDL $4, %ESP # pop from stack
	malloc_null:
		MOVL $-1, %EAX

mp1_ioctl_addmissile_DONE:
		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret
#
#
# movexhairs updates the new crosshair position x and y 
# input: where the xhairs should be moved
# output return: always return 0 for success
mp1_ioctl_movexhairs:
		# setup stackframe
		PUSHL %EBP
		MOVL %ESP, %EBP
		
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI

		MOVL crosshairs_y, %EAX
		IMULL $80, %EAX # 80 positions per row
		ADDL crosshairs_x, %EAX
		IMULL $2, %EAX # %EAX holds current position of crosshairs
		MOVB $SPACE, %CL # set CL to space to erase crosshairs
		CALL mp1_poke

		MOVL 8(%EBP), %EBX # EBX holds the new position of crosshairs 
		MOVSWL %BX, %ESI # take lower word and put it in ESI
		MOVL crosshairs_x, %EDI 
		ADDL %EDI, %ESI # add ESI to current crosshair_x position
		MOVL %ESI, crosshairs_x # update new crosshairs_x position 
		SARL $16, %EBX # shift right 16 bits to get the new Y position 
		MOVL crosshairs_y, %EDI
		ADDL %EDI, %EBX 
		MOVL %EBX, crosshairs_y # update new crosshairs_x y position

	# check if crosshair is out of bound
	x_less_than_zero:	
		CMPL $0, %ESI 
		JG  x_more_than_79
		MOVL $0, crosshairs_x
	x_more_than_79:
		CMPL $79, %ESI
		JL y_less_than_zero
		MOVL $79, crosshairs_x
	y_less_than_zero:
		CMPL $0, %EBX
		JG y_more_than_24
		MOVL $0, crosshairs_y
	y_more_than_24:
		CMPL $24, %EBX
		JL  draw_crosshairs
		MOVL $24, crosshairs_y
	
	draw_crosshairs:
		MOVL crosshairs_y, %EAX
		IMULL $80, %EAX 
		ADDL crosshairs_x, %EAX
		IMULL $2, %EAX # %EAX holds current position of crosshairs
		MOVB $xhair, %CL # set CL to space to erase crosshairs
		CALL mp1_poke

mp1_ioctl_movexhairs_DONE:
		MOVL $0, %EAX # set return value to 0
		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret
#
#
# updates the score and base alive/dead status
# input: new info
# output return: 0 for success, -1 for fail
mp1_ioctl_getstatus:
		# setup stackframe
		PUSHL %EBP
		MOVL %ESP, %EBP
		
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		PUSHL $0 # creating local variable 
		
		MOVL 8(%EBP), %EDI # EBX has user status 
		
		MOVL mp1_score, %EBX # clear EBX register to use for status
		ANDL $0x0000FFFF, %EBX
	city_one_status:
		MOVL base_alive, %ESI # ESI has cities status 
		ANDL $0x000000FF, %ESI # checking lowest byte for status
		CMPL $0, %ESI 
		JE city_two_status
		ORL $0x00010000, %EBX # change bit 16 to 1
	city_two_status:
		MOVL base_alive, %ESI # ESI has cities status 
		ANDL $0x0000FF00, %ESI # checking second byte for status
		CMPL $0, %ESI 
		JE city_three_status
		ORL $0x00020000, %EBX # change bit 17 to 1
	city_three_status:
		MOVL base_alive, %ESI # ESI has cities status 
		ANDL $0x00FF0000, %ESI # checking third byte for status
		CMPL $0, %ESI 
		JE get_score 
		ORL $0x00040000, %EBX # change bit 18 to 1

	get_score:
		MOVL %EBX, -16(%EBP)
		LEAL -16(%EBP), %EBX

		# copying to user
		PUSHL $4 # pushing size n 
		PUSHL %EBX # want to copy register EBX to user
		PUSHL %EDI # desired location for EBX to be sent to 
		CALL mp1_copy_to_user
		ADDL $16, %ESP

		# set return value 0 or -1 for succeed/fail
		CMPL $0, %EAX
		JE mp1_ioctl_getstatus_DONE
		MOVL $-1, %EAX

mp1_ioctl_getstatus_DONE:
		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret
#
#
# endgame frees all the missiles in missile list 
# input: nothing
# ouput return: nothing
mp1_ioctl_endgame:
		# setup stackframe
		PUSHL %EBP
		MOVL %ESP, %EBP
		
		PUSHL %EBX
		PUSHL %ESI 
		PUSHL %EDI
		
		MOVL mp1_missile_list, %EBX

		# freeing every missile in list
	endgame_loop:
		CMPL $0, %EBX
		JE mp1_ioctl_endgame_DONE
		MOVL NEXT(%EBX), %EDI # save the next pointer so it doesn't get lost in free
		PUSHL %EBX
		CALL mp1_free # free current missile
		ADDL $4, %ESP
		MOVL %EDI, %EBX 
		JMP endgame_loop

mp1_ioctl_endgame_DONE:
		POPL %EDI
		POPL %ESI
		POPL %EBX
		leave
		ret

jump_table:
.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame
