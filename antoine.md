# BaseFITS [![Build Status](https://github.com/emmt/BaseFITS.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/emmt/BaseFITS.jl/actions/workflows/CI.yml?query=branch%3Amain) [![Build Status](https://ci.appveyor.com/api/projects/status/github/emmt/BaseFITS.jl?svg=true)](https://ci.appveyor.com/project/emmt/BaseFITS-jl) [![Coverage](https://codecov.io/gh/emmt/BaseFITS.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/emmt/BaseFITS.jl)

`BaseFITS` is a pure [Julia](https://julialang.org/) package for managing basic
FITS structures such as FITS headers. [FITS (for *Flexible Image Transport
System*)](https://fits.gsfc.nasa.gov/fits_standard.html) is a data file format
widely used in astronomy. A FITS file is a concatenation of *Header Data Units*
(HDUs) that consist in a header part and a data part. The header of a HDU is a
collection of so-called *FITS cards*. Each such card is stored in textual form
and associates a keyword with a value and/or a comment.

The `BaseFITS` package is intended to provide:

- Methods for fast parsing of a FITS header or of a piece of a FITS header that
  is a single FITS header card.

- An expressive API for creating FITS cards and accessing their components
  (keyword, value, and comment), possibly, in a *type-stable* way.

- Methods for easy access the records of a FITS header.

```julia

```

### keyword CONTINUE

FITS specification proposes to store a long string with the help of the `CONTINUE` keyword. Example:

```
TOTO    = 'hohohohohohohohohohohohohohohohohohohohohohohohohohohohohoho&'
CONTINUE  'hahahahahahahahaahahahahahahahahahahaha&'
CONTINUE  'huhuhuhuhuhuhuhuhuhuhuhuhuhuhuhuhuhuhuhuhuhuhuhu'
```

The `CONTINUE` keyword can appear multiple times in the header. Thus, setting the `"CONTINUE"` key
on a `FitsHeader` is never an update in place, it is always an appending to the end. See:

```julia
> hdr
2-element FitsHeader:
 FitsCard: ANIMALS = 'a cow and &'
 FitsCard: CONTINUE= 'a deer'

> hdr["ANIMALS"] = "a crab and &"
> hdr["CONTINUE"] = "a duck"

> hdr
3-element FitsHeader:
 FitsCard: ANIMALS = 'a crab and &'
 FitsCard: CONTINUE= 'a deer'
 FitsCard: CONTINUE= 'a duck'
```

To update an existing `"CONTINUE"` keyword value, you must use an integer index. See:

```julia
> indexanimals = findfirst("ANIMALS", hdr)
1

> hdr[indexanimals + 1] = ("CONTINUE" => "a donkey and &")"

> hdr
3-element FitsHeader:
 FitsCard: ANIMALS = 'a crab and &'
 FitsCard: CONTINUE= 'a donkey and &'
 FitsCard: CONTINUE= 'a duck'
```

Note that BaseFITS allows you to store a long string value in a single keyword. When
written to a FITS file, for example by the EasyFITS library, it is correctly modified
to use `"CONTINUE"` keywords. Try `FitsHeader("PANIC" => repeat("A", 1000))`.

## How To

## Links

FITS specification in PDF format: https://fits.gsfc.nasa.gov/standard40/fits_standard40aa-le.pdf

## Edge cases

### Keyword name is a number

The FITS spec allows a keyword name to consists only of digits, for example `"12"`.\
If you need to address such a keyword in a `FitsHeader`, remember to enclose the number
in a string. If you address a `FitsHeader` with an integer, you are asking for an index, not for
a keyword name. See:

```julia
> hdr = FitsHeader()
> push!(hdr, FitsCard("SIMPLE" => true))
> push!(hdr, FitsCard("1" => "abc"))

> hdr[1]
FitsCard: SIMPLE  = T

> hdr["1"]
FitsCard: 1       = 'abc'
```


## TODO

julia> hdr[Fits"MDR"]
ERROR: ArgumentError: invalid index: Fits"MDR" of type FitsKey

Mettre une meilleure erreur ? Expliquer qu'il faut un nom complet.


FITS spec requires the value of the `XTENSION` keyword to be at least of length 8. When parsing 
a header, should we expect to find `"IMAGE   "` value or `"IMAGE"` value ?



FitsCard: TOTO    = 'hahahaha&'
FitsCard: CONTINUE= 'hohohohoho&'
FitsCard: CONTINUE= 'huhuhu'

La norme FITS demande que le mot clé CONTINUE ne soit pas suivi du signe égal.
Corriger l'affichage dans le REPL ? c'est l'affaire d'un if.

