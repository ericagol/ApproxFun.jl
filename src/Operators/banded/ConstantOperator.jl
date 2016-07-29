export ConstantOperator, IdentityOperator, BasisFunctional

##TODO: c->λ
##TODO: ConstantOperator->UniformScalingOperator?
immutable ConstantOperator{T,V,DS} <: Operator{V}
    c::T
    space::DS
    ConstantOperator(c::Number,sp::DS) = new(convert(T,c),sp)
    ConstantOperator(L::UniformScaling,sp::DS) = new(convert(T,L.λ),sp)
end


ConstantOperator{T}(::Type{T},c,sp::Space) = ConstantOperator{eltype(T),T,typeof(sp)}(c,sp)
ConstantOperator{T}(::Type{T},c) = ConstantOperator(T,c,UnsetSpace())
ConstantOperator(c::Number,sp::Space) = ConstantOperator(typeof(c),c,sp)
ConstantOperator(c::Number) = ConstantOperator(typeof(c),c)
ConstantOperator(L::UniformScaling) = ConstantOperator(L.λ)
ConstantOperator(L::UniformScaling,sp::Space) = ConstantOperator(L.λ,sp)
IdentityOperator() = ConstantOperator(1.0)
IdentityOperator(S::Space) = ConstantOperator(1.0,S)

for OP in (:domainspace,:rangespace)
    @eval $OP(C::ConstantOperator) = C.space
end

promotedomainspace(C::ConstantOperator,sp::Space) = ConstantOperator(C.c,sp)

bandinds(T::ConstantOperator) = 0,0

getindex(C::ConstantOperator,k::Integer,j::Integer) = k==j?C.c:zero(eltype(C))


==(C1::ConstantOperator,C2::ConstantOperator) = C1.c==C2.c

function Base.convert{T}(::Type{Operator{T}},C::ConstantOperator)
    if T == eltype(C)
        C
    else
        ConstantOperator{typeof(C.c),T,typeof(C.space)}(C.c,C.space)
    end
end

Base.convert{T}(::Type{Operator{T}},n::Number) =
    n==0?ZeroOperator(A,ConstantSpace()):ConstantOperator(T,n,ConstantSpace())
Base.convert{T}(::Type{Operator{T}},L::UniformScaling) =
    ConstantOperator(T,L.λ)

Operator(n::Number) = Operator{typeof(n)}(n)
Operator(L::UniformScaling) = Operator{eltype(L)}(n)


## Algebra

for op in (:+,:-,:*)
    @eval ($op)(A::ConstantOperator,B::ConstantOperator) = ConstantOperator($op(A.c,B.c))
end


## Basis Functional

immutable BasisFunctional{T} <: Operator{T}
    k::Integer
end

@functional BasisFunctional

BasisFunctional(k) = BasisFunctional{Float64}(k)

bandinds(B::BasisFunctional) = 0,B.k-1
domainspace(B::BasisFunctional) = ℓ⁰

Base.convert{T}(::Type{Operator{T}},B::BasisFunctional) = BasisFunctional{T}(B.k)

Base.getindex(op::BasisFunctional,k::Integer) = (k==op.k)?1.:0.
Base.getindex(op::BasisFunctional,k::Range) = convert(Vector{Float64},k.==op.k)

immutable FillFunctional{T} <: Operator{T}
    c::T
end

@functional FillFunctional

domainspace(B::FillFunctional) = ℓ⁰

Base.getindex(op::FillFunctional,k::Integer)=op.c
Base.getindex(op::FillFunctional,k::Range)=fill(op.c,length(k))

## Zero is a special operator: it makes sense on all spaces, and between all spaces

immutable ZeroOperator{T,S,V} <: Operator{T}
    domainspace::S
    rangespace::V
end

ZeroOperator{T,S,V}(::Type{T},d::S,v::V)=ZeroOperator{T,S,V}(d,v)
ZeroOperator{S,V}(d::S,v::V)=ZeroOperator(Float64,d,v)
ZeroOperator()=ZeroOperator(UnsetSpace(),ZeroSpace())
ZeroOperator{T}(::Type{T})=ZeroOperator(T,UnsetSpace(),ZeroSpace())


Base.convert{T}(::Type{Operator{T}},Z::ZeroOperator) =
    ZeroOperator(T,Z.domainspace,Z.rangespace)





domainspace(Z::ZeroOperator)=Z.domainspace
rangespace(Z::ZeroOperator)=Z.rangespace

bandinds(T::ZeroOperator)=0,0

getindex(C::ZeroOperator,k::Integer,j::Integer)=zero(eltype(C))

promotedomainspace(Z::ZeroOperator,sp::UnsetSpace) = Z
promoterangespace(Z::ZeroOperator,sp::UnsetSpace) = Z
promotedomainspace(Z::ZeroOperator,sp::Space) = ZeroOperator(sp,rangespace(Z))
promoterangespace(Z::ZeroOperator,sp::Space) = ZeroOperator(domainspace(Z),sp)




isconstop(::Union{ZeroOperator,ConstantOperator})=true
isconstop(S::SpaceOperator)=isconstop(S.op)
isconstop(::)=false

Base.convert{T<:Number}(::Type{T},::ZeroOperator)=zero(T)
Base.convert{T<:Number}(::Type{T},C::ConstantOperator)=convert(T,C.c)
Base.convert{T<:Number}(::Type{T},S::SpaceOperator)=convert(T,S.op)
