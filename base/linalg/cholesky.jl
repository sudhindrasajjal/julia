##########################
# Cholesky Factorization #
##########################
immutable Cholesky{T,S<:AbstractMatrix,UpLo} <: Factorization{T}
    UL::S

    function Cholesky(UL::AbstractMatrix{T})
        return new(UL)
    end
end
Cholesky{T}(UL::AbstractMatrix{T},UpLo::Symbol) =
    Cholesky{T,typeof(UL),UpLo}(UL)

immutable CholeskyPivoted{T,S<:AbstractMatrix} <: Factorization{T}
    UL::S
    uplo::Char
    piv::Vector{BlasInt}
    rank::BlasInt
    tol::Real
    info::BlasInt

    function CholeskyPivoted(UL::AbstractMatrix{T},
                            uplo::Char,
                            piv::Vector{BlasInt},
                            rank::BlasInt,
                            tol::Real,
                            info::BlasInt)
        return new(UL, uplo, piv, rank, tol, info)
    end
end

function CholeskyPivoted{T}(UL::AbstractMatrix{T},
                            uplo::Char,
                            piv::Vector{BlasInt},
                            rank::BlasInt,
                            tol::Real,
                            info::BlasInt)
    return CholeskyPivoted{T,typeof(UL)}(UL, uplo, piv, rank, tol, info)
end

function chol!{T<:BlasFloat}(A::StridedMatrix{T})
    C, info = LAPACK.potrf!('U', A)
    return @assertposdef UpperTriangular(C) info
end

function chol!{T<:BlasFloat}(A::StridedMatrix{T}, uplo::Symbol)
    C, info = LAPACK.potrf!(char_uplo(uplo), A)
    if uplo == :U
        return @assertposdef UpperTriangular(C) info
    else
        return @assertposdef LowerTriangular(C) info
    end
end

function chol!{T}(A::AbstractMatrix{T})
    n = chksquare(A)
    @inbounds begin
        for k = 1:n
            for i = 1:k - 1
                A[k,k] -= A[i,k]'A[i,k]
            end
            A[k,k] = chol!(A[k,k], uplo)
            AkkInv = inv(A[k,k])
            for j = k + 1:n
                for i = 1:k - 1
                    A[k,j] -= A[i,k]'A[i,j]
                end
                A[k,j] = A[k,k]'\A[k,j]
            end
        end
    end
    return UpperTriangular(A)
end

function chol!{T}(A::AbstractMatrix{T}, uplo::Symbol)
    n = chksquare(A)
    @inbounds begin
        if uplo == :L
            for k = 1:n
                for i = 1:k - 1
                    A[k,k] -= A[k,i]*A[k,i]'
                end
                A[k,k] = chol!(A[k,k], uplo)
                AkkInv = inv(A[k,k]')
                for j = 1:k
                    for i = k + 1:n
                        if j == 1
                            A[i,k] = A[i,k]*AkkInv
                        end
                        if j < k
                            A[i,k] -= A[i,j]*A[k,j]'*AkkInv
                        end
                    end
                end
            end
            return LowerTriangular(A)
        elseif uplo == :U
            for k = 1:n
                for i = 1:k - 1
                    A[k,k] -= A[i,k]'A[i,k]
                end
                A[k,k] = chol!(A[k,k], uplo)
                AkkInv = inv(A[k,k])
                for j = k + 1:n
                    for i = 1:k - 1
                        A[k,j] -= A[i,k]'A[i,j]
                    end
                    A[k,j] = A[k,k]'\A[k,j]
                end
            end
            return UpperTriangular(A)
        else
            throw(ArgumentError("uplo must be either :U or :L but was $(uplo)"))
        end
    end
end

function cholfact!{T<:BlasFloat}(A::StridedMatrix{T},
                                 uplo::Symbol=:U,
                                 pivot::TrueOrFalse=Val{false};
                                 tol=0.0)
    return _cholfact!(A, pivot, uplo, tol=tol)
end

function _cholfact!{T<:BlasFloat}(A::StridedMatrix{T},
                                  ::Type{Val{false}},
                                  uplo::Symbol=:U; tol=0.0)
    uplochar = char_uplo(uplo)
    return Cholesky(chol!(A, uplo).data, uplo)
end

function _cholfact!{T<:BlasFloat}(A::StridedMatrix{T},
                                  ::Type{Val{true}},
                                  uplo::Symbol=:U;
                                  tol=0.0)
    uplochar = char_uplo(uplo)
    A, piv, rank, info = LAPACK.pstrf!(uplochar, A, tol)
    return CholeskyPivoted{T,StridedMatrix{T}}(A, uplochar, piv, rank, tol, info)
end

cholfact!(A::AbstractMatrix, uplo::Symbol=:U) = Cholesky(chol!(A, uplo).data, uplo)

function cholfact!{T<:BlasFloat,S,UpLo}(C::Cholesky{T,S,UpLo})
    _, info = LAPACK.potrf!(char_uplo(UpLo), C.UL)
    if info[1] > 0
        throw(PosDefException(info[1]))
    end
    return C
end

function cholfact{T<:BlasFloat}(A::StridedMatrix{T},
                                uplo::Symbol=:U,
                                pivot::TrueOrFalse=Val{false};
                                tol=0.0)
    return cholfact!(copy(A), uplo, pivot, tol=tol)
end

copy_oftype{T}(A::StridedMatrix{T}, ::Type{T}) = copy(A)
copy_oftype{T,S}(A::StridedMatrix{T}, ::Type{S}) = convert(AbstractMatrix{S}, A)

function cholfact{T}(A::StridedMatrix{T},
                     uplo::Symbol=:U,
                     pivot::TrueOrFalse=Val{false};
                     tol=0.0)
    TT = promote_type(typeof(chol(one(T))), Float32)
    return _cholfact(copy_oftype(A, TT), pivot, uplo, tol=tol)
end

_cholfact{T<:BlasFloat}(A::StridedMatrix{T}, pivot::Type{Val{true}}, uplo::Symbol=:U; tol=0.0) =
    cholfact!(A, uplo, pivot, tol = tol)

_cholfact{T<:BlasFloat}(A::StridedMatrix{T}, pivot::Type{Val{false}}, uplo::Symbol=:U; tol=0.0) =
    cholfact!(A, uplo, pivot, tol = tol)

_cholfact{T}(A::StridedMatrix{T}, ::Type{Val{false}}, uplo::Symbol=:U; tol=0.0) =
    cholfact!(A, uplo)

_cholfact{T}(A::StridedMatrix{T}, ::Type{Val{true}}, uplo::Symbol=:U; tol=0.0) =
    throw(ArgumentError(
        "pivoting only supported for Float32, Float64, Complex{Float32} and Complex{Float64} element types"))

function cholfact(x::Number, uplo::Symbol=:U)
    xf = fill(chol!(x, uplo), 1, 1)
    return Cholesky(xf, uplo)
end

function chol{T}(A::AbstractMatrix{T}, uplo::Symbol=:U)
    S = promote_type(typeof(chol(one(T))), Float32)
    if S == T
        return chol!(copy(A), uplo)
    else
        return chol!(convert(AbstractMatrix{S}, A), uplo)
    end
end

function chol!(x::Number, uplo::Symbol=:U)
    rx = real(x)
    if rx != abs(x)
        throw(DomainError())
    end
    rxr = sqrt(rx)
    convert(promote_type(typeof(x), typeof(rxr)), rxr)
end
chol(x::Number, uplo::Symbol=:U) = chol!(x, uplo)

function convert{Tnew,Told,S,UpLo}(::Type{Cholesky{Tnew}}, C::Cholesky{Told,S,UpLo})
    Cnew = convert(AbstractMatrix{Tnew}, C.UL)
    return Cholesky{Tnew, typeof(Cnew), UpLo}(Cnew)
end

function convert{T,S,UpLo}(::Type{Cholesky{T,S,UpLo}},C::Cholesky)
    Cnew = convert(AbstractMatrix{T}, C.UL)
    return Cholesky{T, typeof(Cnew), UpLo}(Cnew)
end

convert{T}(::Type{Factorization{T}}, C::Cholesky) = convert(Cholesky{T}, C)

convert{T}(::Type{CholeskyPivoted{T}}, C::CholeskyPivoted) =
    CholeskyPivoted(convert(AbstractMatrix{T}, C.UL), C.uplo, C.piv, C.rank, C.tol, C.info)

convert{T}(::Type{Factorization{T}}, C::CholeskyPivoted) =
    convert(CholeskyPivoted{T}, C)

full{T,S}(C::Cholesky{T,S,:U}) = C[:U]'C[:U]
full{T,S}(C::Cholesky{T,S,:L}) = C[:L] * C[:L]'

size(C::Union(Cholesky, CholeskyPivoted)) = size(C.UL)
size(C::Union(Cholesky, CholeskyPivoted), d::Integer) = size(C.UL,d)

function getindex{T,S,UpLo}(C::Cholesky{T,S,UpLo}, d::Symbol)
    if d == :U
        if UpLo == d
            return UpperTriangular(C.UL)
        else
            return UpperTriangular(C.UL')
        end
    elseif d == :L
        if UpLo == d
            return LowerTriangular(C.UL)
        else
            return LowerTriangular(C.UL')
        end
    elseif d == :UL
        if UpLo == :U
            return UpperTriangular(C.UL)
        else
            LowerTriangular(C.UL)
        end
    end
    throw(KeyError(d))
end

function getindex{T<:BlasFloat}(C::CholeskyPivoted{T}, d::Symbol)
    if d == :U
        if symbol(C.uplo) == d
            return UpperTriangular(C.UL)
        else
            return UpperTriangular(C.UL')
        end
    elseif d == :L
        if symbol(C.uplo) == d
            return LowerTriangular(C.UL)
        else
            return LowerTriangular(C.UL')
        end
    elseif d == :p
        return C.piv
    elseif d == :P
        n = size(C, 1)
        P = zeros(T, n, n)
        for i=1:n
            P[C.piv[i],i] = one(T)
        end
        return P
    end
    throw(KeyError(d))
end

function show{T,S<:AbstractMatrix,UpLo}(io::IO, C::Cholesky{T,S,UpLo})
    println("$(typeof(C)) with factor:")
    show(io, C[UpLo])
end

A_ldiv_B!{T<:BlasFloat,S<:AbstractMatrix}(C::Cholesky{T,S,:U}, B::StridedVecOrMat{T}) =
    LAPACK.potrs!('U', C.UL, B)

A_ldiv_B!{T<:BlasFloat,S<:AbstractMatrix}(C::Cholesky{T,S,:L}, B::StridedVecOrMat{T}) =
    LAPACK.potrs!('L', C.UL, B)

A_ldiv_B!{T,S<:AbstractMatrix}(C::Cholesky{T,S,:L}, B::StridedVecOrMat) =
    Ac_ldiv_B!(LowerTriangular(C.UL), A_ldiv_B!(LowerTriangular(C.UL), B))

A_ldiv_B!{T,S<:AbstractMatrix}(C::Cholesky{T,S,:U}, B::StridedVecOrMat) =
    A_ldiv_B!(UpperTriangular(C.UL), Ac_ldiv_B!(UpperTriangular(C.UL), B))

function A_ldiv_B!{T<:BlasFloat}(C::CholeskyPivoted{T}, B::StridedVector{T})
    if rank(C) < size(C.UL, 1)
        throw(RankDeficientException(C.info))
    end
    return ipermute!(LAPACK.potrs!(C.uplo, C.UL, permute!(B, C.piv)), C.piv)
end

function A_ldiv_B!{T<:BlasFloat}(C::CholeskyPivoted{T}, B::StridedMatrix{T})
    if rank(C) < size(C.UL, 1)
        throw(RankDeficientException(C.info))
    end
    n = size(C, 1)
    for i=1:size(B, 2)
        permute!(sub(B, 1:n, i), C.piv)
    end
    LAPACK.potrs!(C.uplo, C.UL, B)
    for i=1:size(B, 2)
        ipermute!(sub(B, 1:n, i), C.piv)
    end
    return B
end

function A_ldiv_B!(C::CholeskyPivoted, B::StridedVector)
    if C.uplo == 'L'
        return Ac_ldiv_B!(LowerTriangular(C.UL),
                          A_ldiv_B!(LowerTriangular(C.UL), B[C.piv]))[invperm(C.piv)]
    else
        return A_ldiv_B!(UpperTriangular(C.UL),
                         Ac_ldiv_B!(UpperTriangular(C.UL), B[C.piv]))[invperm(C.piv)]
    end
end

function A_ldiv_B!(C::CholeskyPivoted, B::StridedMatrix)
    if C.uplo == 'L'
        return Ac_ldiv_B!(LowerTriangular(C.UL),
                          A_ldiv_B!(LowerTriangular(C.UL), B[C.piv,:]))[invperm(C.piv),:]
    else
        return A_ldiv_B!(UpperTriangular(C.UL),
                         Ac_ldiv_B!(UpperTriangular(C.UL), B[C.piv,:]))[invperm(C.piv),:]
    end
end

function det{T,S,UpLo}(C::Cholesky{T,S,UpLo})
    dd = one(T)
    for i in 1:size(C.UL,1)
        dd *= abs2(C.UL[i,i])
    end
    return dd
end

function det{T}(C::CholeskyPivoted{T})
    if rank(C) < size(C.UL,1)
        return real(zero(T))
    else
        return prod(abs2(diag(C.UL)))
    end
end

function logdet{T,S,UpLo}(C::Cholesky{T,S,UpLo})
    dd = zero(T)
    for i in 1:size(C.UL,1)
        dd += log(C.UL[i,i])
    end
    return dd + dd # instead of 2.0dd which can change the type
end

inv{T<:BlasFloat,S<:AbstractMatrix}(C::Cholesky{T,S,:U}) =
    copytri!(LAPACK.potri!('U', copy(C.UL)), 'U', true)

inv{T<:BlasFloat,S<:AbstractMatrix}(C::Cholesky{T,S,:L}) =
    copytri!(LAPACK.potri!('L', copy(C.UL)), 'L', true)

function inv(C::CholeskyPivoted)
    if rank(C) < size(C.UL, 1)
        throw(RankDeficientException(C.info))
    end
    ipiv = invperm(C.piv)
    return copytri!(LAPACK.potri!(C.uplo, copy(C.UL)), C.uplo, true)[ipiv, ipiv]
end

rank(C::CholeskyPivoted) = C.rank
