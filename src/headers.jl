module Headers

export FITSHeader

using ..FITSBase
using ..FITSBase: check_keyword, is_comment

using Base: @propagate_inbounds
using Base.Order: Ordering, Forward, Reverse

struct Keyword
    key::FITSKey # quick key
    name::String # full name
end
Keyword(card::FITSCard) = Keyword(card.key, card.name)
Keyword(name::AbstractString) = Keyword(check_keyword(name)...)

"""
    FITSHeader(args...) -> hdr

yields a FITS header object initialized with records `args..`. If the only
argument is an instance of `Vector{FITSCard}`, `hdr` directly uses it for its own
storage.

A FITS header object behaves as a vector of [`FITSCard`](@ref) elements with
integer or keyword (string) indices. When indexed by keywords, a FITS header
object is similar to a dictionary except that the order of records is preserved
and that commentary and continuation records (with keywords `"COMMENT"`,
`"HISTORY"`, `""`, or `"CONTINUE"`) may appears more than once.

To  append a new record `rec` to the FITS header `hdr`, call:

    push!(hdr, rec)

where `rec` may be an instance of [`FITSCard`](@ref) or a pair `key => (val,
com)` associating keyword `key` with a value `val` and/or a comment `com`.

If the intention is to update the record, call:

    hdr[key] = (val, com)

which modifies the record if the keyword `key` already exists in `hdr` and
appends the record to `hdr` otherwise. Note that COMMENT and HISTORY commentary
records are always appended (as if `push!` has been called). To modify any
existing record including commentary ones, use the syntax:

    hdr[i] = rec

where `i` is a linear (integer) index.

Searching for the index `i` of an existing record in FITS header object `hdr`
can be done by the usual methods:

    findfirst(what, hdr)
    findlast(what, hdr)
    findnext(what, hdr, start)
    findprev(what, hdr, start)

which all return a valid integer index if a record matching `what` is found and
`nothing` otherwise. The matching pattern `what` can be a keyword (string), a
FITS card (an instance of [`FITSCard`](@ref) whose name is used as a matching
pattern), or a predicate function which takes a FITS card argument and shall
return whether it matches. The find methods just yield `nothing` for any
unsupported kind of pattern.

"""
struct FITSHeader <: AbstractVector{FITSCard}
    cards::Vector{FITSCard}
    index::Dict{String,Int} # index to first (and unique for non-commentary and
                            # non-continuation keywords) entry with given
                            # keyword

    # Build empty header.
    FITSHeader() = new(FITSCard[], Dict{String,Int}())

    # Copy constructor.
    FITSHeader(hdr::FITSHeader) = new(copy(hdr.cards), copy(hdr.index))
end

# By default, assume an iterator.
function FITSHeader(iter)
    hdr = FITSHeader()
    has_length(iter) && (len = length(iter)) > 0 && sizehint!(hdr, len)
    for rec ∈ iter
        push!(hdr, FITSCard(rec))
    end
    return hdr
end

function FITSHeader(recs...)
    hdr = FITSHeader()
    (len = length(recs)) > 0 && sizehint!(hdr, len)
    for rec ∈ recs
        push!(hdr, FITSCard(rec))
    end
    return hdr
end

FITSHeader(rec::Union{FITSCard,Pair}) = push!(FITSHeader(), FITSCard(rec))

Base.copy(hdr::FITSHeader) = FITSHeader(hdr)

is_unique(card::FITSCard) = is_unique(card.key)
is_unique(kwrd::Keyword) = is_unique(kwrd.key)
is_unique(key::FITSKey) =
    (key !== FITS"COMMENT") &
    (key !== FITS"HISTORY") &
    (key !== FITS"CONTINUE") &
    (key !== FITS"")

Base.convert(::Type{<:FITSHeader}, hdr::FITSHeader) = hdr
Base.convert(::Type{<:FITSHeader}, iter) = FITSHeader(iter)

function Base.sizehint!(hdr::FITSHeader, n::Integer)
    sizehint!(hdr.cards, n)
    sizehint!(hdr.index, n)
    return hdr
end

function Base.empty!(hdr::FITSHeader)
    if length(hdr) > 0
        empty!(hdr.cards)
        empty!(hdr.index)
    end
    return hdr
end

# Implement part of the abstract dictionary API.
Base.keys(hdr::FITSHeader) = keys(hdr.index)
Base.getkey(hdr::FITSHeader, kwrd::Keyword, def) = getkey(hdr.index, krwd.name, def)
Base.getkey(hdr::FITSHeader, key::AbstractString, def) =
    try
        getkey(hdr.index, Keyword(key), def)
    catch
        def
    end

# Implement abstract array API.
Base.IndexStyle(::Type{<:FITSHeader}) = IndexLinear()
for func in (:length, :size, :axes)
    @eval Base.$func(hdr::FITSHeader) = $func(hdr.cards)
end
Base.firstindex(hdr::FITSHeader) = 1
Base.lastindex(hdr::FITSHeader) = length(hdr)

@inline function Base.getindex(hdr::FITSHeader, i::Int)
    @boundscheck checkbounds(hdr, i)
    @inbounds getindex(hdr.cards, i)
end

@inline function Base.setindex!(hdr::FITSHeader, rec, i::Int)
    @boundscheck checkbounds(hdr, i)
    unsafe_setindex!(hdr, to_type(FITSCard, rec), i)
    return hdr
end

# This unsafe method assumes that index i is valid.
function unsafe_setindex!(hdr::FITSHeader, card::FITSCard, i::Int)
    i_first = findfirst(card, hdr)
    if i_first == nothing
        # No card exists in the header with this name.
        delete!(hdr.index, (@inbounds hdr[i]).name) # remove old name in index
        hdr.index[card.name] = i
    elseif i != i_first
        # Index may have to be updated.
        is_unique(card) && error("FITS keyword \"$(card.name)\" already exists at index $(i_first)")
        if i < i_first
            # Inserted card will be the first one occurring in the header with
            # this name.
            hdr.index[card.name] = i
        end
    end
    @inbounds hdr.cards[i] = card
end

Base.setindex!(hdr::FITSHeader, val, name::AbstractString) = push!(hdr, name => val)

function Base.getindex(hdr::FITSHeader, name::AbstractString)
    card = get(hdr, name, nothing)
    card === nothing ? throw(KeyError(name)) : card
end

function Base.get(hdr::FITSHeader, i::Integer, def)
    i = to_type(Int, i)
    checkbounds(Bool, hdr, i) ? (@inbounds hdr[i]) : def
end

function Base.get(hdr::FITSHeader, name::AbstractString, def)
    # NOTE: Call findfirst() to deal with HIERARCH convention.
    i = findfirst(name, hdr)
    i === nothing ? def : (@inbounds hdr[i])
end

Base.get(hdr::FITSHeader, key, def) = def

"""
    push!(hdr::FITSHeader, rec) -> hdr

appends a new record `rec` in into FITS header `hdr` or, if the keyword of the
card must be unique and a record with the same name already exists in `hdr`,
replaces the existing record.

This is strictly equivalent to:

    hdr[key] = (val, com)

with `key` the name of the record, and `val` and `com` the associated value and
comment.

Note that COMMENT, HISTORY, blank, and CONTINUE records are always appended.

"""
Base.push!(hdr::FITSHeader, rec) = push!(hdr, to_type(FITSCard, rec))
function Base.push!(hdr::FITSHeader, card::FITSCard)
    # Replace existing card with the same keyword if it must be unique.
    # Otherwise, push a new card.
    i = findfirst(card, hdr)
    if i == nothing
        # No card exists with this name, push a new one and index it.
        hdr.index[card.name] = lastindex(push!(hdr.cards, card))
    elseif is_unique(card)
        # A card with this name must be unique, replace existing card.
        @inbounds hdr.cards[i] = card
    else
        # Append the commentary or continuation card to the header.
        push!(hdr.cards, card)
    end
    return hdr
end

"""
    findfirst(what, hdr::FITSHeader) -> i :: Union{Int,Nothing}

finds the first occurence of a record in FITS header `hdr` matching the pattern
`what`.

"""
Base.findfirst(what, hdr::FITSHeader) = nothing

"""
    findlast(what, hdr::FITSHeader) -> i :: Union{Int,Nothing}

find the last occurence of a record in FITS header `hdr` matching the pattern
`what`.

"""
Base.findlast(what, hdr::FITSHeader) = nothing

"""
    findnext(what, hdr::FITSHeader, start) -> i :: Union{Int,Nothing}

find the next occurence of a record in FITS header `hdr` matching the pattern
`what` at or after index `start`.

""" Base.findnext

"""
    findprev(what, hdr::FITSHeader, start) -> i :: Union{Int,Nothing}

find the previous occurence of a record in FITS header `hdr` matching the
pattern `what` at or before index `start`.

""" Base.findprev

const RecordID = Union{FITSCard,Keyword}

Base.findfirst(pat::RecordID, hdr::FITSHeader) = get(hdr.index, pat.name, nothing)

function Base.findlast(pat::RecordID, hdr::FITSHeader)
    first = findfirst(pat, hdr)
    first === nothing && return nothing
    is_unique(pat) && return first
    # Enter slow part...
    @inbounds for i ∈ lastindex(hdr):-1:first+1
        is_matching(hdr.cards[i], pat) && return i
    end
    return first
end

Base.findfirst(func::Function, hdr::FITSHeader) = unsafe_findnext(func, hdr, firstindex(hdr))
Base.findlast(func::Function, hdr::FITSHeader) = unsafe_findprev(func, hdr, lastindex(hdr))

# NOTE: First stage of `findnext` and `findprev` avoids costly conversion if
# result can be decided without actually searching. Need to specify type of
# `what` in function signature to avoid ambiguities.
for T in (Any, AbstractString, Keyword, FITSCard, Function)
    @eval function Base.findnext(what::$T, hdr::FITSHeader, start::Integer)
        start = to_type(Int, start)
        start > lastindex(hdr) && return nothing
        start < firstindex(hdr) && throw(BoundsError(hdr, start))
        return unsafe_findnext(what, hdr, start)
    end
    @eval function Base.findprev(what::$T, hdr::FITSHeader, start::Integer)
        start = to_type(Int, start)
        start < firstindex(hdr) && return nothing
        start > lastindex(hdr) && throw(BoundsError(hdr, start))
        return unsafe_findprev(what, hdr, start)
    end
end

# When search pattern is a string, we must catch errors in Keyword() in case
# the pattern is not a valid FITS keyword.
for func in (:findfirst, :findlast)
    @eval function Base.$func(name::AbstractString, hdr::FITSHeader)
        try
            return $func(Keyword(name), hdr)
        catch
            return nothing
        end
    end
end
for func in (:unsafe_findnext, :unsafe_findprev)
    @eval function $func(name::AbstractString, hdr::FITSHeader, start::Int)
        try
            return $func(Keyword(name), hdr, start)
        catch
            return nothing
        end
    end
end

# By default, find nothing.
unsafe_findnext(pat, hdr::FITSHeader, start::Int) = nothing
unsafe_findprev(pat, hdr::FITSHeader, start::Int) = nothing

function unsafe_findnext(pat::RecordID, hdr::FITSHeader, start::Int)
    first = findfirst(pat, hdr)
    first === nothing && return nothing
    start ≤ first && return first
    is_unique(pat) && return nothing
    # Enter slow part...
    @inbounds for i ∈ start:lastindex(hdr)
        is_matching(hdr.cards[i], pat) && return i
    end
    return nothing
end

function unsafe_findprev(pat::RecordID, hdr::FITSHeader, start::Int)
    first = findfirst(pat, hdr)
    first === nothing && return nothing
    start < first && return nothing
    is_unique(pat) && return first
    # Enter slow part...
    @inbounds for i ∈ start:-1:first+1
        is_matching(hdr.cards[i], pat) && return i
    end
    return first
end

function unsafe_findnext(func::Function, hdr::FITSHeader, start::Int)
    @inbounds for i ∈ start:lastindex(hdr)
        func(hdr.cards[i]) && return i
    end
    return nothing
end

function unsafe_findprev(func::Function, hdr::FITSHeader, start::Int)
    @inbounds for i ∈ start:-1:firstindex(hdr)
        func(hdr.cards[i]) && return i
    end
    return nothing
end

is_matching(card::FITSCard, pat::RecordID) =
    pat.key != FITS"HIERARCH" ? card.key == pat.key :
    card.name === pat.name || (card.key == FITS"HIERARCH" && isequal(card.name, pat.name))

"""
    eachmatch(what, hdr::FITSHeader)

yields an iterator over the records of `hdr` matching `what`.

For example:

    @inbounds for rec in eachmatch(what, hdr)
        ... # do something
    end

is equivalent to:

    i = findfirst(what, hdr)
    @inbounds while i !== nothing
        rec = hdr[i]
        ... # do something
        i = findnext(what, hdr, i+1)
    end

while:

    @inbounds for rec in reverse(eachmatch(what, hdr))
        ... # do something
    end

is equivalent to:

    i = findlast(what, hdr)
    @inbounds while i !== nothing
        rec = hdr[i]
        ... # do something
        i = findprev(what, hdr, i-1)
    end

"""
Base.eachmatch(what, hdr::FITSHeader) = HeaderIterator(what, hdr)

struct HeaderIterator{O<:Ordering,P}
    pattern::P
    header::FITSHeader
    HeaderIterator(order::O, pattern::P, header::FITSHeader) where {O,P} =
        new{O,P}(pattern, header)
end
HeaderIterator(pattern, header::FITSHeader) = HeaderIterator(Forward, pattern, header)
HeaderIterator(order::Ordering, name::AbstractString, hdr::FITSHeader) =
    HeaderIterator(order, try; Keyword(name); catch; NEVER_MATCHING_KEYWORD; end, hdr)

const NEVER_MATCHING_KEYWORD = Keyword(0x3d3d3d3d3d3d3d3d, "========")

Base.IteratorEltype(::Type{<:HeaderIterator}) = Base.HasEltype()
Base.eltype(::Type{<:HeaderIterator}) = FITSCard

Base.IteratorSize(::Type{<:HeaderIterator}) = Base.SizeUnknown()

Base.reverse(iter::HeaderIterator{typeof(Forward)}) =
    HeaderIterator(Reverse, iter.pattern, iter.header)
Base.reverse(iter::HeaderIterator{typeof(Reverse)}) =
    HeaderIterator(Forward, iter.pattern, iter.header)

# Iterate over entries in forward order.
function Base.iterate(iter::HeaderIterator{typeof(Forward)})
    j = findfirst(iter.pattern, iter.header)
    j === nothing ? nothing : ((@inbounds iter.header[j]), j+1)
end
function Base.iterate(iter::HeaderIterator{typeof(Forward)}, i::Int)
    j = findnext(iter.pattern, iter.header, i)
    j === nothing ? nothing : ((@inbounds iter.header[j]), j+1)
end

# Iterate over entries in reverse order.
function Base.iterate(iter::HeaderIterator{typeof(Reverse)})
    j = findlast(iter.pattern, iter.header)
    j === nothing ? nothing : ((@inbounds iter.header[j]), j-1)
end
function Base.iterate(iter::HeaderIterator{typeof(Reverse)}, i::Int)
    j = findprev(iter.pattern, iter.header, i)
    j === nothing ? nothing : ((@inbounds iter.header[j]), j-1)
end

"""
    collect(what, hdr::FITSHeader; order::Ordering = Forward)

yields a vector of the records of `hdr` matching `what` and sorted according to
`order` (`Base.Order.Forward` or `Base.Order.Reverse`).

"""
function Base.collect(what, hdr::FITSHeader; order::Ordering = Forward)
    iter = HeaderIterator(order, what, hdr)
    dest = FITSCard[]
    has_length(iter) && sizehint!(dest, length(iter))
    for rec in iter
        push!(dest, rec)
    end
    return dest
end

function Base.filter(what, hdr::FITSHeader; order::Ordering = Forward)
    iter = HeaderIterator(order, what, hdr)
    dest = FITSHeader()
    has_length(iter) && sizehint!(dest, length(iter))
    for rec in iter
        push!(dest, rec)
    end
    return dest
end

has_length(iter) = Base.IteratorSize(iter) isa Union{Base.HasShape,Base.HasLength}

to_type(::Type{T}, x::T) where {T} = x
to_type(::Type{T}, x) where {T} = convert(T, x)::T

end # module