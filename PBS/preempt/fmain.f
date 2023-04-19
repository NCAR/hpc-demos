      subroutine do_checkpoint
      integer :: i

      i = 1
      do while (i .le. 10)
         print *, "     ", i, ": Inside checkpoint function"
         call flush(6)
         call sleep(5)
         i = i+1
      end do

      call done_checkpoint()

      end subroutine do_checkpoint



! simple F77 main to demonstrate interacting with a C-based signal handler
      program main
      implicit none
      integer :: i, checkpoint_requested
      external checkpoint_requested

      call register_sig_handler()

      i = 1
      do while (i .le. 50)
         print *, i, ": Inside main function"
         call flush(6)
         call sleep(5)
         i = i+1

         if (1 .eq. checkpoint_requested()) then
           call do_checkpoint()
         endif
      end do
      end program main
