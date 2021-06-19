

# -------------- Implementation of Product Basis

struct Product1pBasis{NB, TB <: Tuple, NSYM, SYMS} <: OneParticleBasis{Any}
   bases::TB
   spec::Vector{NamedTuple{SYMS, NTuple{NSYM, Int}}}
   indices::Vector{NTuple{NB, Int}}
end

function Product1pBasis(bases;
                        SYMS = _symbols_prod(bases), )
   # TODO: discuss whether to construct an optimal ordering, e.g.
   #       should the discrete bases come first once we implement the
   #       "strongzero" method?
   NSYM = length(SYMS)
   NB = length(bases)
   Product1pBasis( tuple(bases...),
                   NamedTuple{SYMS, NTuple{NSYM, Int}}[],
                   NTuple{NB, Int}[] )
end


import Base.*
*(B1::OneParticleBasis, B2::OneParticleBasis) =
      Product1pBasis((B1, B2))
*(B1::Product1pBasis, B2::OneParticleBasis) =
      Product1pBasis((B1.bases..., B2))
*(B1::OneParticleBasis, B2::Product1pBasis) =
      Product1pBasis((B1, B2.bases...))
*(B1::Product1pBasis, B2::Product1pBasis) =
      Product1pBasis((B1.bases..., B2.bases...))


_numb(b::Product1pBasis{NB}) where {NB} = NB

Base.length(basis::Product1pBasis) = length(basis.spec)

# ------------------------- FIO CODES

==(B1::Product1pBasis, B2::Product1pBasis) = 
      ( all(B1.bases .== B2.bases) && 
        convert.(Dict, B1.spec) == convert.(Dict, B2.spec) && 
        B1.indices == B2.indices )

write_dict(B::Product1pBasis) = 
      Dict("__id__" => "ACE_Product1pBasis", 
            "bases" => write_dict.(B.bases), 
             "spec" => convert.(Ref(Dict), B.spec),
          "indices" => B.indices )

function read_dict(::Val{:ACE_Product1pBasis}, D::Dict)
   bases = tuple( read_dict.(D["bases"])... )
   spec = namedtuple.( D["spec"] )
   indices = [ tuple(v...) for v in D["indices"] ]
   return Product1pBasis(bases, spec, indices)
end


# ------------------------------------


valtype(basis::Product1pBasis, X::AbstractState) = 
      promote_type(valtype.(basis.bases, Ref(X))...)

valtype(basis::Product1pBasis, cfg::AbstractConfiguration) = 
      promote_type( valtype.(basis.bases, Ref(iterate(cfg)[1]))... )

gradtype(basis::Product1pBasis, cfg::Union{AbstractConfiguration, AbstractVector}) = 
      gradtype(basis, zero(eltype(cfg)))

function gradtype(basis::Product1pBasis, X::AbstractState) 
   VALT = valtype(basis, X)
   return dstate_type(VALT, X)
end

alloc_temp(basis::Product1pBasis, arg) =
      (
         B = alloc_B.(basis.bases, Ref(arg)),
         tmp = alloc_temp.(basis.bases, Ref(arg))
      )


alloc_dB(basis::Product1pBasis, cfg::AbstractConfiguration) = 
      zeros(gradtype(basis, cfg), (length(basis), length(cfg)) )



alloc_temp_d(basis::Product1pBasis, cfg::AbstractConfiguration) = 
      alloc_temp_d(basis, zero(eltype(cfg)) )

alloc_temp_d(basis::Product1pBasis, X::AbstractState) = 
      (
         B = alloc_B.(basis.bases, Ref(X)),
         tmp = alloc_temp.(basis.bases, Ref(X)),
         dB = alloc_dB.(basis.bases, Ref(X)),
         tmpd = alloc_temp_d.(basis.bases, Ref(X))
      )





@generated function add_into_A!(A, tmp, basis::Product1pBasis{NB}, X) where {NB}
   quote
      Base.Cartesian.@nexprs $NB i -> evaluate!(tmp.B[i], tmp.tmp[i], basis.bases[i], X)
      for (iA, ϕ) in enumerate(basis.indices)
         t = one(eltype(A))
         Base.Cartesian.@nexprs $NB i -> (t *= tmp.B[i][ϕ[i]])
         A[iA] += t
      end
      return nothing
   end
end



@generated function add_into_A_dA!(A, dA, tmpd, basis::Product1pBasis{NB}, X
                                   ) where {NB}
   quote
      Base.Cartesian.@nexprs($NB, i -> begin   # for i = 1:NB
         if !(basis.bases[i] isa Discrete1pBasis)
            # only evaluate basis gradients for a continuous basis
            evaluate_ed!(tmpd.B[i], tmpd.dB[i], tmpd.tmpd[i], basis.bases[i], X)
         else
            # we still need the basis values for the discrete basis though
            evaluate!(tmpd.B[i], tmpd.tmpd[i], basis.bases[i], X)
         end
      end)
      for (iA, ϕ) in enumerate(basis.indices)
         # evaluate A
         t = one(eltype(A))
         Base.Cartesian.@nexprs($NB, i -> begin   # for i = 1:NB
            t *= tmpd.B[i][ϕ[i]]
         end)
         A[iA] += t

         # evaluate dA
         # TODO: redo this with adjoints!!!!
         #     also reverse order of operations to make fewer multiplications!
         dA[iA] = zero(eltype(dA))
         Base.Cartesian.@nexprs($NB, a -> begin  # for a = 1:NB
            if !(basis.bases[a] isa Discrete1pBasis)
               dt = tmpd.dB[a][ϕ[a]]
               Base.Cartesian.@nexprs($NB, b -> begin  # for b = 1:NB
                  if b != a
                     dt *= tmpd.B[b][ϕ[b]]
                  end
               end)
               dA[iA] += dt
            end
         end)
      end
      return nothing
   end
end


@generated function add_into_A_dA!(A, dA, tmpd, basis::Product1pBasis{NB}, X
                                   ) where {NB}
   quote
      Base.Cartesian.@nexprs($NB, i -> begin   # for i = 1:NB
         if !(basis.bases[i] isa Discrete1pBasis)
            # only evaluate basis gradients for a continuous basis
            evaluate_ed!(tmpd.B[i], tmpd.dB[i], tmpd.tmpd[i], basis.bases[i], X)
         else
            # we still need the basis values for the discrete basis though
            evaluate!(tmpd.B[i], tmpd.tmpd[i], basis.bases[i], X)
         end
      end)
      for (iA, ϕ) in enumerate(basis.indices)
         # evaluate A
         t = one(eltype(A))
         Base.Cartesian.@nexprs($NB, i -> begin   # for i = 1:NB
            t *= tmpd.B[i][ϕ[i]]
         end)
         A[iA] += t

         # evaluate dA
         # TODO: redo this with adjoints!!!!
         #     also reverse order of operations to make fewer multiplications!
         dA[iA] = zero(eltype(dA))
         Base.Cartesian.@nexprs($NB, a -> begin  # for a = 1:NB
            if !(basis.bases[a] isa Discrete1pBasis)
               dt = tmpd.dB[a][ϕ[a]]
               Base.Cartesian.@nexprs($NB, b -> begin  # for b = 1:NB
                  if b != a
                     dt *= tmpd.B[b][ϕ[b]]
                  end
               end)
               dA[iA] += dt
            end
         end)
      end
      return nothing
   end
end


function evaluate_d!(dA, tmpd, basis::Product1pBasis, X)
   A = alloc_B(basis, X)
   add_into_A_dA!(A, dA, tmpd, basis, X)
   return dA 
end


_symbols_prod(bases) = tuple(union( symbols.(bases)... )...)

symbols(basis::Product1pBasis{NB, TB, NSYM, SYMS}
            ) where {NB, TB, NSYM, SYMS} = SYMS

function indexrange(basis::Product1pBasis)
   allsyms = tuple(symbols(basis)...)
   rg = Dict{Symbol, Vector{Int}}([ sym => Int[] for sym in allsyms]...)
   for b in basis.bases
      rgb = indexrange(b)
      for sym in allsyms
         if haskey(rgb, sym)
            rg[sym] = union(rg[sym], rgb[sym])
         end
      end
   end
   # HACK: fix the m range based on the maximal l-range
   #       this needs to be suitably generalised if we have multiple
   #       (l, m) pairs, e.g. (l1, m1), (l2, m2)
   if haskey(rg, :m)
      maxl = maximum(rg[:l])
      rg[:m] = collect(-maxl:maxl)
   end

   # convert the range into a named tuple so that we remember the order!!
   return NamedTuple{allsyms}(ntuple(i -> rg[allsyms[i]], length(allsyms)))
end

isadmissible(b, basis::Product1pBasis) = all(isadmissible.(Ref(b), basis.bases))

function set_spec!(basis::Product1pBasis{NB}, spec) where {NB}
   empty!(basis.spec)
   append!(basis.spec, spec)
   empty!(basis.indices)
   for b in basis.spec
      inds = ntuple(i -> get_index(basis.bases[i], b), NB)
      push!(basis.indices, inds)
   end
   return basis
end

get_spec(basis::Product1pBasis) = basis.spec

get_spec(basis::Product1pBasis, i::Integer) = basis.spec[i]

degree(b, basis::Product1pBasis) = sum( degree(b, B) for B in basis.bases )

degree(b::NamedTuple, basis::Product1pBasis, weight::Dict) = 
      sum( degree(b, B, weight) for B in basis.bases )

# TODO: this looks like a horrible hack ...
function rand_radial(basis::Product1pBasis)
   for B in basis.bases
      if B isa ScalarACEBasis
         return rand_radial(B)
      end
   end
   return nothing
end




# --------------- AD codes

import ChainRules: rrule, NO_FIELDS, ZeroTangent

_evaluate_bases(basis::Product1pBasis{NB}, X::AbstractState) where {NB} = 
      ntuple(i -> evaluate(basis.bases[i], X), NB)

_evaluate_A(basis::Product1pBasis{NB}, BB) where {NB} = 
      [ prod(BB[i][ϕ[i]] for i = 1:NB) for ϕ in basis.indices ]

evaluate(basis::Product1pBasis, X::AbstractState) = 
      _evaluate_A(basis, _evaluate_bases(basis, X)) 

function _rrule_evaluate(basis::Product1pBasis{NB}, X::AbstractState, 
                         w::AbstractVector{<: Number}, 
                         BB = _evaluate_bases(basis, X)) where {NB}
   VT = promote_type(valtype(basis, X), eltype(w))

   # dB = evaluate_d(basis, X)
   # return sum( (real(w) * real(db) + imag(w) * imag(db)) 
   #             for (w, db) in zip(w, dB) )

   # Compute the differentials for the individual sub-bases 
   Wsub = ntuple(i -> zeros(VT, length(BB[i])), NB) 
   for (ivv, vv) in enumerate(basis.indices)
      for t = 1:NB 
         _A = one(VT)
         for s = 1:NB 
            if s != t 
               _A *= BB[s][vv[s]]
            end
         end
         Wsub[t][vv[t]] += w[ivv] * conj(_A)
      end
   end

   # now these can be propagated into the inner basis 
   #  -> type instab to be fixed here 
   g = sum( _rrule_evaluate(basis.bases[t], X, Wsub[t] )
            for t = 1:NB )
   return g
end

function rrule(::typeof(evaluate), basis::Product1pBasis, X::AbstractState)
   BB = _evaluate_bases(basis, X)
   A = _evaluate_A(basis, BB)
   return A, 
      w -> (NO_FIELDS, NO_FIELDS, _rrule_evaluate(basis, X, w, BB))
end


#    function _rrule_evaluate(basis::Scal1pBasis, X::AbstractState, 
#       w::AbstractVector{<: Number})
# x = _val(X, basis)
# a = _rrule_evaluate(basis.P, x, w)
# TDX = ACE.dstate_type(a, X)
# return TDX( NamedTuple{(_varsym(basis),)}( (a,) ) )
# end
