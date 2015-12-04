!
! Copyright (C) 2015 Andrea Dal Corso 
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
SUBROUTINE fit_frequencies_anis()
  !
  ! use the phonon frequencies calculated for a uniform mesh at ngeo 
  ! geometries and computes the coefficients of a second order polynomial 
  ! that fit the frequencies as a function of the crystal parameters
  ! 
  USE kinds,                  ONLY : DP
  USE thermo_mod,             ONLY : ngeo, celldm_geo
  USE ions_base,              ONLY : nat
  USE cell_base,              ONLY : ibrav
  USE ph_freq_thermodynamics, ONLY : ph_freq_save
  USE grun_anharmonic,        ONLY : poly_grun
  USE control_thermo,         ONLY : with_eigen
  USE mp_images,              ONLY : root_image, my_image_id

  IMPLICIT NONE

  REAL(DP), ALLOCATABLE :: freq_geo(:,:)
  COMPLEX(DP), ALLOCATABLE ::  displa_geo(:,:,:)
  INTEGER :: n, igeo, nq, degree, nvar, nwork
  INTEGER :: compute_nwork

  IF ( my_image_id /= root_image ) RETURN
!
!  allocate space for the fit of the frequencies with respect to the
!  celldm parameters
!
  nq=ph_freq_save(1)%nq
  CALL compute_degree(ibrav,degree,nvar)
  nwork=compute_nwork()

  IF ( .NOT. ALLOCATED( poly_grun ) ) ALLOCATE(poly_grun(nvar,3*nat,nq))

  ALLOCATE(freq_geo(3*nat,nwork))
  IF (with_eigen) ALLOCATE(displa_geo(3*nat,3*nat,nwork))
!
  DO n = 1, nq
     DO igeo=1,nwork
        freq_geo(1:3*nat,igeo)=ph_freq_save(igeo)%nu(1:3*nat,n)
        IF (with_eigen) displa_geo(1:3*nat, 1:3*nat, igeo)= &
                             ph_freq_save(igeo)%displa(1:3*nat,1:3*nat,n)
     ENDDO
     IF (with_eigen) THEN
        CALL compute_freq_derivative_anis_eigen(nwork,freq_geo, &
                               celldm_geo,displa_geo,degree,nvar,ibrav, &
                               poly_grun(1,1,n))
     ELSE
        CALL compute_freq_derivative_anis(nwork,freq_geo, &
                    celldm_geo,degree,nvar,ibrav,poly_grun(1,1,n))
     END IF
  ENDDO

  IF (with_eigen) DEALLOCATE ( displa_geo )
  DEALLOCATE ( freq_geo )

  RETURN
END SUBROUTINE fit_frequencies_anis

SUBROUTINE compute_freq_derivative_anis_eigen(ngeo,freq_geo,celldm_geo,&
                     displa_geo,degree,nvar,ibrav,poly_grun)

USE kinds, ONLY : DP
USE ions_base, ONLY : nat
USE quadratic_surfaces, ONLY : fit_multi_quadratic
IMPLICIT NONE
INTEGER,  INTENT(IN) :: ngeo, degree, nvar, ibrav
REAL(DP), INTENT(IN) :: freq_geo(3*nat,ngeo), celldm_geo(6,ngeo)
COMPLEX(DP), INTENT(IN) :: displa_geo(3*nat,3*nat,ngeo)
REAL(DP), INTENT(INOUT) :: poly_grun(nvar,3*nat)

REAL(DP), ALLOCATABLE :: frequences(:), x(:,:), f(:)
REAL(DP) :: overlap
INTEGER :: imode, jmode, igeo, idata, central_geo
COMPLEX(DP), EXTERNAL :: ZDOTC

ALLOCATE (frequences(ngeo))
ALLOCATE (x(degree,ngeo))
ALLOCATE (f(ngeo))

central_geo=ngeo/2+1

DO imode=1, 3*nat
   frequences=0.0_DP
   DO igeo=1, ngeo
      IF (igeo /= central_geo) THEN
         DO jmode=1,3*nat
            overlap=ABS(ZDOTC(3*nat,displa_geo(1,jmode,igeo),1,&
                                      displa_geo(1,imode,central_geo),1))**2
            frequences(igeo)=frequences(igeo) + freq_geo(jmode,igeo)* overlap
         ENDDO
      ELSE
         frequences(igeo)=freq_geo(imode,igeo)
      ENDIF
   END DO
!
   SELECT CASE (ibrav)
      CASE(1,2,3)
         DO idata=1,ngeo
            x(1,idata)=celldm_geo(1,idata)
            f(idata)=frequences(idata)
         ENDDO
      CASE(4,5,6,7)
         DO idata=1,ngeo
            x(1,idata)=celldm_geo(1,idata)
            IF (ibrav==5) THEN
               x(2,idata)=ACOS(celldm_geo(4,idata))
            ELSE
               x(2,idata)=celldm_geo(3,idata)
            ENDIF
            f(idata)=frequences(idata)
         END DO
      CASE(8,9,91,10,11)
         DO idata=1,ngeo
            x(1,idata)=celldm_geo(1,idata)
            x(2,idata)=celldm_geo(2,idata)
            x(3,idata)=celldm_geo(3,idata)
            f(idata)=frequences(idata)
         ENDDO
      CASE(12,-12,13,-13)
         DO idata=1,ngeo
            x(1,idata)=celldm_geo(1,idata)
            x(2,idata)=celldm_geo(2,idata)
            x(3,idata)=celldm_geo(3,idata)
            IF (ibrav>0) THEN
!
!   c unique
!
               x(4,idata)=ACOS(celldm_geo(4,idata))
            ELSE
!
!   b unique
!
               x(4,idata)=ACOS(celldm_geo(5,idata))
            ENDIF
            f(idata)=frequences(idata)
         END DO
      CASE DEFAULT
         DO idata=1,ngeo
            x(1,idata)=celldm_geo(1,idata)
            x(2,idata)=celldm_geo(2,idata)
            x(3,idata)=celldm_geo(3,idata)
            x(4,idata)=ACOS(celldm_geo(4,idata))
            x(5,idata)=ACOS(celldm_geo(5,idata))
            x(6,idata)=ACOS(celldm_geo(6,idata))
            f(idata)=frequences(idata) 
         ENDDO
   END SELECT
   CALL fit_multi_quadratic(ngeo,degree,nvar,x,f,poly_grun(:,imode))
ENDDO

DEALLOCATE ( x )
DEALLOCATE ( f )
DEALLOCATE ( frequences )

RETURN
END SUBROUTINE compute_freq_derivative_anis_eigen

SUBROUTINE compute_freq_derivative_anis(ngeo,freq_geo,celldm_geo,degree,nvar,&
                                             ibrav,poly_grun)
USE kinds, ONLY : DP
USE ions_base, ONLY : nat
USE quadratic_surfaces, ONLY : fit_multi_quadratic
IMPLICIT NONE
INTEGER,  INTENT(IN) :: ngeo, degree, nvar, ibrav
REAL(DP), INTENT(IN) :: freq_geo(3*nat,ngeo), celldm_geo(6,ngeo)
REAL(DP), INTENT(INOUT) :: poly_grun(nvar,3*nat)

REAL(DP), ALLOCATABLE :: frequences(:), x(:,:), f(:)
INTEGER :: imode, igeo, idata

ALLOCATE (frequences(ngeo))
ALLOCATE (x(degree,ngeo))
ALLOCATE (f(ngeo))

DO imode=1, 3*nat
   frequences=0.0_DP
   DO igeo=1, ngeo
      frequences(igeo)=freq_geo(imode,igeo)
   ENDDO
!
   SELECT CASE (ibrav)
      CASE(1,2,3)
         DO idata=1,ngeo
            x(1,idata)=celldm_geo(1,idata)
            f(idata)=frequences(idata)
         ENDDO
      CASE(4,5,6,7)
         DO idata=1,ngeo
            x(1,idata)=celldm_geo(1,idata)
            IF (ibrav==5) THEN
               x(2,idata)=ACOS(celldm_geo(4,idata))
            ELSE
               x(2,idata)=celldm_geo(3,idata)
            ENDIF
            f(idata)=frequences(idata)
         END DO
      CASE(8,9,91,10,11)
         DO idata=1,ngeo
            x(1,idata)=celldm_geo(1,idata)
            x(2,idata)=celldm_geo(2,idata)
            x(3,idata)=celldm_geo(3,idata)
            f(idata)=frequences(idata)
         ENDDO
      CASE(12,-12,13,-13)
         DO idata=1,ngeo
            x(1,idata)=celldm_geo(1,idata)
            x(2,idata)=celldm_geo(2,idata)
            x(3,idata)=celldm_geo(3,idata)
            IF (ibrav>0) THEN
!
!   c unique
!
               x(4,idata)=ACOS(celldm_geo(4,idata))
            ELSE
!
!   b unique
!
               x(4,idata)=ACOS(celldm_geo(5,idata))
            ENDIF
            f(idata)=frequences(idata)
         END DO
      CASE DEFAULT
         DO idata=1,ngeo
            x(1,idata)=celldm_geo(1,idata)
            x(2,idata)=celldm_geo(2,idata)
            x(3,idata)=celldm_geo(3,idata)
            x(4,idata)=ACOS(celldm_geo(4,idata))
            x(5,idata)=ACOS(celldm_geo(5,idata))
            x(6,idata)=ACOS(celldm_geo(6,idata))
            f(idata)=frequences(idata) 
         ENDDO
   END SELECT
   CALL fit_multi_quadratic(ngeo,degree,nvar,x,f,poly_grun(:,imode))
ENDDO

DEALLOCATE ( x )
DEALLOCATE ( f )
DEALLOCATE ( frequences )

RETURN
END SUBROUTINE compute_freq_derivative_anis
