

export Fourier,Taylor,Hardy,CosSpace,SinSpace,Laurent

for T in (:CosSpace,:SinSpace)
    @eval begin
        immutable $T{D<:Domain} <: RealUnivariateSpace{D}
            domain::D
            $T(d::Domain) = new(D(d))
            $T(d::D) = new(d)
        end
        $T(d::Domain) = $T{typeof(d)}(d)
        $T() = $T(PeriodicInterval())
        spacescompatible(a::$T,b::$T) = domainscompatible(a,b)
        hasfasttransform(::$T) = true
        canonicalspace(S::$T) = Fourier(domain(S))
        setdomain(S::$T,d::Domain) = $T(d)
    end
end

doc"""
`CosSpace()` is the space spanned by `[1,cos θ,cos 2θ,...]`
"""
CosSpace()

doc"""
`SinSpace()` is the space spanned by `[sin θ,sin 2θ,...]`
"""
SinSpace()

# s == true means analytic inside, taylor series
# s == false means anlytic outside and decaying at infinity
immutable Hardy{s,D<:Domain} <: UnivariateSpace{ComplexBasis,D}
    domain::D
    Hardy(d) = new(d)
    Hardy() = new(D())
end

# The <: Domain is crucial for matching Basecall overrides
typealias Taylor{D<:Domain} Hardy{true,D}


# Following is broken in 0.4
if VERSION ≥ v"0.5"
    doc"""
    `Taylor()` is the space spanned by `[1,z,z^2,...]`.  This is a type alias for `Hardy{true}`.

    """
    Taylor

    doc"""
    `Hardy{false}()` is the space spanned by `[1/z,1/z^2,...]`
    """
    Hardy{false}
end


Base.promote_rule{T<:Number,S<:Union{Hardy{true},CosSpace},V}(::Type{Fun{S,V}},::Type{T}) =
    Fun{S,promote_type(V,T)}
Base.promote_rule{T<:Number,S<:Union{Hardy{true},CosSpace}}(::Type{Fun{S}},::Type{T}) =
    Fun{S,T}

@compat (H::Type{Hardy{s}}){s}(d::Domain) = Hardy{s,typeof(d)}(d)
@compat (H::Type{Hardy{s}}){s}() = Hardy{s}(Circle())

canonicalspace(S::Hardy) = S
setdomain{s}(S::Hardy{s},d::Domain) = Hardy{s}(d)


spacescompatible{s}(a::Hardy{s},b::Hardy{s}) = domainscompatible(a,b)
hasfasttransform(::Hardy) = true


for Typ in (:HardyTransformPlan,:IHardyTransformPlan)
    @eval begin
        immutable $Typ{T,s,inplace,PL} <: FFTW.Plan{T}
            plan::PL
        end
        @compat (::Type{$Typ{s,inp}}){s,inp}(plan) =
            $Typ{eltype(plan),s,inp,typeof(plan)}(plan)
    end
end

for (Typ,Plfft!,Plfft,Pltr!,Pltr) in ((:HardyTransformPlan,:plan_fft!,:plan_fft,:plan_transform!,:plan_transform),
                           (:IHardyTransformPlan,:plan_ifft!,:plan_ifft,:plan_itransform!,:plan_itransform))
    @eval begin
        $Pltr!{s,T<:Complex}(::Hardy{s},x::Vector{T}) = $Typ{s,true}($Plfft!(x))
        $Pltr!{s,T<:Real}(::Hardy{s},x::Vector{T}) =
            error("In place variants not possible with real data.")

        $Pltr{s,T<:Complex}(sp::Hardy{s},x::Vector{T}) = $Typ{s,false}($Pltr!(sp,x))
        function $Pltr{s,T}(sp::Hardy{s},x::Vector{T})
            plan = $Pltr(sp,Array{Complex{T}}(length(x))) # we can reuse vector in itransform
            $Typ{T,s,false,typeof(plan)}(plan)
        end

        *{T<:Complex,s}(P::$Typ{T,s,false},vals::Vector{T}) = P.plan*copy(vals)
        *{T,s}(P::$Typ{T,s,false},vals::Vector{T}) = P.plan*Vector{Complex{T}}(vals)
    end
end


*{T}(P::HardyTransformPlan{T,true,true},vals::Vector{T}) = scale!(one(T)/length(vals),P.plan*vals)
*{T}(P::IHardyTransformPlan{T,true,true},cfs::Vector{T}) = scale!(length(cfs),P.plan*cfs)
*{T}(P::HardyTransformPlan{T,false,true},vals::Vector{T}) = scale!(one(T)/length(vals),reverse!(P.plan*vals))
*{T}(P::IHardyTransformPlan{T,false,true},cfs::Vector{T}) = scale!(length(cfs),P.plan*reverse!(cfs))


transform(sp::Hardy,vals::Vector,plan) = plan*vals
itransform(sp::Hardy,vals::Vector,plan) = plan*vals

evaluate{D<:Domain}(f::AbstractVector,S::Taylor{D},z) = horner(f,fromcanonical(Circle(),tocanonical(S,z)))
function evaluate{D<:Circle}(f::AbstractVector,S::Taylor{D},z)
    z=mappoint(S,𝕌,z)
    d=domain(S)
    horner(f,z)
end

function evaluate{D<:Domain}(f::AbstractVector,S::Hardy{false,D},z)
    z=mappoint(S,𝕌,z)
    z=1./z
    z.*horner(f,z)
end
function evaluate{D<:Circle}(f::AbstractVector,S::Hardy{false,D},z)
    z=mappoint(S,𝕌,z)
    z=1./z
    z.*horner(f,z)
end


##TODO: fast routine

function horner(c::AbstractVector,kr::Range{Int64},x)
    T = promote_type(eltype(c),eltype(x))
    if isempty(c)
        return zero(x)
    end

    ret = zero(T)
    @inbounds for k in reverse(kr)
        ret = muladd(x,ret,c[k])
    end

    ret
end

function horner(c::AbstractVector,kr::Range{Int64},x::AbstractVector)
    n,T = length(x),promote_type(eltype(c),eltype(x))
    if isempty(c)
        return zero(x)
    end

    ret = zeros(T,n)
    @inbounds for k in reverse(kr)
        ck = c[k]
        @simd for i = 1:n
            ret[i] = muladd(x[i],ret[i],ck)
        end
    end

    ret
end

horner(c::AbstractVector,x) = horner(c,1:length(c),x)
horner(c::AbstractVector,x::AbstractArray) = horner(c,1:length(c),x)
horner(c::AbstractVector,kr::Range{Int64},x::AbstractArray) = reshape(horner(c,kr,vec(x)),size(x))

## Cos and Sin space

points(sp::CosSpace,n) = points(domain(sp),2n-2)[1:n]  #TODO: reorder Fourier
plan_transform(::CosSpace,x::Vector) = plan_chebyshevtransform(x;kind=2)
plan_itransform(::CosSpace,x::Vector) = plan_ichebyshevtransform(x;kind=2)
transform(::CosSpace,vals,plan) = plan*vals
itransform(::CosSpace,cfs,plan) = plan*cfs
evaluate(f::Vector,S::CosSpace,t) = clenshaw(Chebyshev(),f,cos(tocanonical(S,t)))


points(sp::SinSpace,n)=points(domain(sp),2n+2)[2:n+1]
plan_transform{T<:FFTW.fftwNumber}(::SinSpace,x::Vector{T}) = FFTW.plan_r2r(x,FFTW.RODFT00)
plan_itransform{T<:FFTW.fftwNumber}(::SinSpace,x::Vector{T}) = FFTW.plan_r2r(x,FFTW.RODFT00)

plan_transform{D}(::SinSpace{D},x::Vector) =
    error("transform for Fourier only implemented for fftwNumbers")
plan_itransform{D}(::SinSpace{D},x::Vector) =
    error("transform for Fourier only implemented for fftwNumbers")



transform(::SinSpace,vals,plan) = plan*vals/(length(vals)+1)
itransform(::SinSpace,cfs,plan) = plan*cfs/2
evaluate(f::AbstractVector,S::SinSpace,t) = sineshaw(f,tocanonical(S,t))



## Laurent space
doc"""
`Laurent()` is the space spanned by the complex exponentials
```
    1,exp(-im*θ),exp(im*θ),exp(-2im*θ),…
```
See also `Fourier`.
"""
typealias Laurent{DD} SumSpace{Tuple{Hardy{true,DD},Hardy{false,DD}},ComplexBasis,DD,1}


plan_transform{DD}(::Laurent{DD},x::Vector) = plan_svfft(x)
plan_itransform{DD}(::Laurent{DD},x::Vector) = plan_isvfft(x)
transform{DD}(::Laurent{DD},vals,plan...) = svfft(vals,plan...)
itransform{DD}(::Laurent{DD},cfs,plan...) = isvfft(cfs,plan...)


function evaluate{DD}(f::AbstractVector,S::Laurent{DD},z)
    z = mappoint(domain(S),Circle(),z)
    invz = 1./z
    horner(f,1:2:length(f),z) + horner(f,2:2:length(f),invz).*invz
end


function Base.conj{DD}(f::Fun{Laurent{DD}})
    cfs=Array(eltype(f),iseven(ncoefficients(f))?ncoefficients(f)+1:ncoefficients(f))
    cfs[1]=conj(f.coefficients[1])
    cfs[ncoefficients(f)] = 0
    for k=2:2:ncoefficients(f)-1
        cfs[k]=conj(f.coefficients[k+1])
    end
    for k=3:2:ncoefficients(f)+1
        cfs[k]=conj(f.coefficients[k-1])
    end
    Fun(space(f),cfs)
end

## Fourier space

doc"""
`Fourier()` is the space spanned by the trigonemtric polynomials
```
    1,sin(θ),cos(θ),sin(2θ),cos(2θ),…
```
See also `Laurent`.
"""
typealias Fourier{DD} SumSpace{Tuple{CosSpace{DD},SinSpace{DD}},RealBasis,DD,1}

for Typ in (:Laurent,:Fourier)
    @eval begin
        @compat (::Type{$Typ})(d::Domain) = $Typ{typeof(d)}(d)
        @compat (::Type{$Typ})() = $Typ(PeriodicInterval())
        @compat (::Type{$Typ})(d) = $Typ(PeriodicDomain(d))

        hasfasttransform{D}(::$Typ{D}) = true
    end
end

for T in (:CosSpace,:SinSpace)
    @eval begin
        # override default as canonicalspace must be implemented
        maxspace{D}(::$T,::Fourier{D}) = NoSpace()
        maxspace{D}(::Fourier{D},::$T) = NoSpace()
    end
end

points{D}(sp::Fourier{D},n)=points(domain(sp),n)
plan_transform{T<:FFTW.fftwNumber,D}(::Fourier{D},x::Vector{T}) =
    FFTW.plan_r2r(x, FFTW.R2HC)
plan_itransform{T<:FFTW.fftwNumber,D}(::Fourier{D},x::Vector{T}) =
    FFTW.plan_r2r(x, FFTW.HC2R)

plan_transform{D}(::Fourier{D},x::Vector) =
    error("transform for Fourier only implemented for fftwNumbers")
plan_itransform{D}(::Fourier{D},x::Vector) =
    error("transform for Fourier only implemented for fftwNumbers")

transform{T<:Number,D}(S::Fourier{D},vals::Vector{T}) =
    transform(S,vals,plan_transform(S,vals))

function transform{T<:Number,D}(::Fourier{D},vals::Vector{T},plan)
    n = length(vals)
    cfs = scale!(T(2)/n,plan*vals)
    cfs[1] /= 2
    if iseven(n)
        cfs[div(n,2)+1] /= 2
    end

    negateeven!(reverseeven!(interlace!(cfs,1)))
end

itransform{T<:Number,D}(S::Fourier{D},vals::Vector{T}) =
    itransform(S,vals,plan_itransform(S,vals))

function itransform{T<:Number,D}(::Fourier{D},a::Vector{T},plan)
    n = length(a)
    cfs = [a[1:2:end];-flipdim(a[2:2:end],1)]
    if iseven(n)
        cfs[n÷2+1] *= 2
    end
    cfs[1] *= 2
    plan*scale!(inv(T(2)),cfs)
end



canonicalspace{DD<:PeriodicInterval}(S::Laurent{DD})=Fourier(domain(S))
canonicalspace{DD<:Circle}(S::Fourier{DD})=Laurent(domain(S))
canonicalspace{DD<:PeriodicLine}(S::Laurent{DD})=S

for Typ in (:CosSpace,:Taylor)
    @eval union_rule(A::ConstantSpace,B::$Typ)=B
end

## Ones and zeros

for sp in (:Fourier,:CosSpace,:Laurent,:Taylor)
    @eval begin
        Base.ones{T<:Number,D}(::Type{T},S::$sp{D})=Fun(S,ones(T,1))
        Base.ones{D}(S::$sp{D})=Fun(S,ones(1))
    end
end


function identity_fun{DD<:Circle}(S::Taylor{DD})
    d=domain(S)
    if d.orientation
        Fun(S,[d.center,d.radius])
    else
        error("Cannot create identity on $S")
    end
end


identity_fun{DD<:Circle}(S::Fourier{DD}) = Fun(identity_fun(Laurent(domain(S))),S)


reverseorientation{D}(f::Fun{Fourier{D}}) =
    Fun(Fourier(reverse(domain(f))),alternatesign!(copy(f.coefficients)))
function reverseorientation{D}(f::Fun{Laurent{D}})
    # exp(im*k*x) -> exp(-im*k*x), or equivalentaly z -> 1/z
    n=ncoefficients(f)
    ret=Array(eltype(f),iseven(n)?n+1:n)  # since z -> 1/z we get one more coefficient
    ret[1]=f.coefficients[1]
    for k=2:2:length(ret)-1
        ret[k+1]=f.coefficients[k]
    end
    for k=2:2:n-1
        ret[k]=f.coefficients[k+1]
    end
    iseven(n) && (ret[n] = 0)

    Fun(Laurent(reverse(domain(f))),ret)
end

include("calculus.jl")
include("specialfunctions.jl")
include("FourierOperators.jl")
include("LaurentOperators.jl")
include("LaurentDirichlet.jl")
