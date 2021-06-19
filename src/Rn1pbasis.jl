
import ACE.OrthPolys: TransformedPolys



@doc raw"""
`struct Rn1pBasis <: OneParticleBasis`

One-particle basis of the form $R_n(r_{ij})$, i.e.,
no dependence on species or on $l$.

This does two things: (1) translates the `TransformedPolys` into a valid
one-particle basis; and (2) treat it as having vectorial input, i.e. value is 
scalar but gradient is vectorial.

The default symbols are `:rr` for the state and `:n` for the index of the 
basis function. 
"""
mutable struct Rn1pBasis{T, TT, TJ, VSYM, NSYM} <: OneParticleBasis{T}
   R::TransformedPolys{T, TT, TJ}
end


Rn1pBasis(R::TransformedPolys{T, TT, TJ}; varsym = :rr, nsym = :n
            ) where {T, TT, TJ} = 
      Rn1pBasis{T, TT, TJ, varsym, nsym}(R)

# ---------------------- Implementation of Rn1pBasis

Base.length(basis::Rn1pBasis) = length(basis.R)

_varsym(::Rn1pBasis{T, TT, TJ, VSYM, NSYM}) where {T, TT, TJ, VSYM, NSYM} = VSYM
_nsym(::Rn1pBasis{T, TT, TJ, VSYM, NSYM}) where {T, TT, TJ, VSYM, NSYM} = NSYM
_n(b, basis::Rn1pBasis) = getproperty(b, _nsym(basis))
_rr(X, Rn::Rn1pBasis) = getproperty(X, _varsym(Rn))

# -> TODO : figure out how to do this well!!!
# Base.rand(basis::Ylm1pBasis) =
#       AtomState(rand(basis.zlist.list), ACE.Random.rand_vec(basis.J))

function get_spec(basis::Rn1pBasis) 
   N = _nsym(basis)
   return [  NamedTuple{(N,)}((n,)) for n = 1:length(basis) ]
end

==(P1::Rn1pBasis, P2::Rn1pBasis) =  ACE._allfieldsequal(P1, P2)

write_dict(basis::Rn1pBasis{T}) where {T} = Dict(
      "__id__" => "ACE_Rn1pBasis",
          "R" => write_dict(basis.R), 
          "varsym" => _varsym(basis), 
          "nsym" => _nsym(basis) )

read_dict(::Val{:ACE_Rn1pBasis}, D::Dict) = 
            Rn1pBasis(read_dict(D["R"]), 
                      varsym = Symbol(D["varsym"]), 
                      nsym = Symbol(D["nsym"]))

valtype(basis::Rn1pBasis{T}, ::AbstractConfiguration) where T = T
valtype(basis::Rn1pBasis{T}, X::AbstractState) where T = T

gradtype(B::Rn1pBasis, X::AbstractState) = dstate_type(valtype(B, X), X)

symbols(Rn::Rn1pBasis) = [ _nsym(Rn) ]

indexrange(Rn::Rn1pBasis) = NamedTuple{(_nsym(Rn),)}((1:length(Rn),))

isadmissible(b, basis::Rn1pBasis) = (1 <= _n(b, basis) <= length(basis))

degree(b, Rn::Rn1pBasis) = _n(b, Rn) - 1

degree(b, Rn::Rn1pBasis, weight::Dict) = weight[_nsym(Rn)] * degree(b, Rn)

get_index(basis::Rn1pBasis, b) = _n(b, basis)

rand_radial(basis::Rn1pBasis) = rand_radial(basis.R)

# ---------------------------  Evaluation code
#


evaluate!(B, tmp, basis::Rn1pBasis, X::AbstractState) =
      evaluate!(B, tmp, basis.R, norm(_rr(X, basis)))

function evaluate(basis::Rn1pBasis, X::AbstractState)
   rr = _rr(X, basis)
   return evaluate(basis.R, norm(rr))
end


function evaluate_d!(dB, tmpd, basis::Rn1pBasis, X::AbstractState)
   TDX = eltype(dB)
   RR = _varsym(basis)
   rr = _rr(X, basis)
   r = norm(rr)
   r̂ = rr / r
   dRdr = evaluate_d(basis.R, r)
   for n = 1:length(basis)
      dB[n] = TDX( NamedTuple{(RR,)}( (dRdr[n] * r̂,) ) )
   end
   return dB
end


# ----------------- AD 

import ChainRules: rrule, NO_FIELDS

function _rrule_evaluate(basis::Rn1pBasis, X::AbstractState, 
                         w::AbstractVector{<: Number})
   rr = _rr(X, basis)
   r = norm(rr)
   a = _rrule_evaluate(basis.R, r, real.(w))
   TDX = ACE.dstate_type(a/r, X)
   return TDX( NamedTuple{(_varsym(basis),)}( (a * rr / r,)) )
end

rrule(::typeof(evaluate), basis::Rn1pBasis, X::AbstractState) = 
                  evaluate(basis, X), 
                  w -> (NO_FIELDS, NO_FIELDS, _rrule_evaluate(basis, X, w))

                  
function _rrule_evaluate_d(basis::Rn1pBasis, X::AbstractState, 
                           w::AbstractVector, 
                           dRn = evaluate_d(basis.R, norm(_rr(X, basis))))
   rr = _rr(X, basis); r = norm(rr); r̂ = rr/r
   w_r̂ = [ dot(_rr(w, basis), r̂)  for w in w ]
   w2 = [ _rr(w[n], basis) - w_r̂[n] * r̂ for n = 1:length(w) ]
   a = _rrule_evaluate_d(basis.R, r, w_r̂)
   b = sum(dRn .* w2) / r 
   TDX = ACE.dstate_type(a, X)
   return TDX( NamedTuple{(_varsym(basis),)}( (a * r̂ + b,) ) )
end

function rrule(::typeof(evaluate_d), basis::Rn1pBasis, X::AbstractState)
   rr = _rr(X, basis); r = norm(rr); r̂ = rr/r
   dRn_ = evaluate_d(basis.R, r);
   TDX = dstate_type(valtype(basis, X), X)
   dRn = [ TDX( NamedTuple{(_varsym(basis),)}( (dr * r̂,) ) ) 
           for dr in dRn_ ]
   return dRn, 
          w -> (NO_FIELDS, NO_FIELDS, _rrule_evaluate_d(basis, X, w, dRn_))
end
