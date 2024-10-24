module AST

import Base: hash, ==, string, length, getindex, eltype, show, get, iterate

import DataStructures as ds
import DataStructures: containsp, walk, emptyp, count, ireduce, first, rest

##### Run time data structures

abstract type Node end

function show(io::IO, mime::MIME"text/plain", s::Node)
  print(io, string(s))
end

### Built ins

abstract type BuiltIn <: Node end

"""
Primitive functions expect their arguments to be literal values. They should
normally be wrapped to make sure args are evaluated.
"""
struct PrimitiveFunction <: BuiltIn
  f::Function
end

"""
Primitive macros operate directly on the AST of the program. They also receive
the lexical envronment when invoked.
"""
struct PrimitiveMacro <: BuiltIn
  f::Function
end

### Top level ("def"ed) forms
##
## The main purpose here is to keep metadata of what you would call "vars" in
## Clojure, easily accessible at the namespace level.

"""
Container for defined forms and those typed into the repl.
"""
struct TopLevel <: Node
  meta
  form
end

string(x::TopLevel) = string(x.form)

### Immediate (eval asap) forms

struct Immediate <: Node
  form
end

immediate(f) = Immediate(f)

string(f::Immediate) = "~" * string(f.form)

function walk(inner, outer, f::Immediate)
  outer(Immediate(inner(f.form)))
end

### Pairs.
##
## N.B. These are *not* cons cells. They're just pairs. What would be a cons
## list in lisp is here a pair whose tail is a vector (list).
##
## REVIEW: Maybe `head` and `tail` ought to be rethought in light of the above.

struct Pair <: Node
  head
  tail
end

pair(h, t) = Pair(h, t)

function tailstring(x)
  " . " * string(x)
end

function string(c::Pair)
  "(" * string(c.head) * tailstring(c.tail) * ")"
end

function walk(inner, outer, form::Pair)
  outer(Pair(inner(form.head), inner(form.tail)))
end

function tailstring(c::ds.Sequential)
  ds.into(" ", map(string) ∘ ds.interpose(" "), c)
end

### Application
##
### I.e. things that are to be applied as soon as possible

"""
Represents an application of args to a function-like entity which has not been
performed yet.
"""
struct Application <: Node
  head
  tail
end

function string(x::Application)
  "#Application(" * string(x.head) * ", " * string(x.tail) * ")"
end

function Base.:(==)(x::Application, y::Application)
  x.head == y.head && x.tail == y.tail
end

const apphash = hash("#Application")

function hash(x::Application)
  xor(apphash, hash(x.head), hash(x.tail))
end

### Mu
##
### The basic syntactic combinator of the language.

struct Mu <: Node
  arg::ds.Symbol
  body
end

string(x::Mu) = "(μ " * string(x.arg) * " " * string(x.body) * ")"

function Base.:(==)(x::Mu, y::Mu)
  x.arg == y.arg && x.body == y.body
end

const muhash = hash("#Mu")

function hash(x::Mu)
  xor(muhash, hash(x.arg), hash(x.body))
end

### Partially applied Mu
##
### This exists because a Mu is ill defined unless its argument is a symbol. A
### partial μ is a binary node whose left tree will (presumably) evaluate to a
### symbol at some point in the future. At that point we can construct a proper
### μ operator. In the meantime, however, we need to treat the two cases as
### fundamentally different.

struct PartialMu <: Node
  arg
  body
end

string(x::PartialMu) = "(μ " * string(x.arg) * " " * string(x.body) * ")"

function Base.:(==)(x::PartialMu, y::PartialMu)
  x.arg == y.arg && x.body == y.body
end

function hash(x::PartialMu)
  xor(muhash, hash(x.arg), hash(x.body))
end

##### Embedded Symbols
##
## If a symbol is written (read) in a context in which is has a meaning, then we
## have a lexical symbol which has a known (fixed) meaning *unless* it has been
## shadowed dynamically.
##
## A symbol which is not defined in the dev time environment is free. Free
## symbols must be bound by a μ before any attempt to evaluate them.
##
## There is no way to programmatically construct a symbol at runtime. That means
## that you can never refer to something that doesn't exist at the time you're
## writing the code. You can exist to a quantity that you don't know yet (and
## indeed might not yet exist) using the μ operator. That's enough, though often
## awkward to use.
##
## What that means concretely is that *any* FreeSymbol *must* be the lefthand
## arg to *at least one* μ. I'm not yet willing to rule out shadowing like Roc.
## It would make it easier to write the compiler, but I'm not willing to let my
## own ease define the language.

struct LexicalSymbol <: Node
  name::ds.Symbol
  env::ds.Map
end

string(x::LexicalSymbol) = string(x.name)

function Base.:(==)(x::LexicalSymbol, y::LexicalSymbol)
  x.name == y.name && x.value == y.value
end

hash(x::LexicalSymbol) = hash(x.name)

struct FreeSymbol <: Node
  name::ds.Symbol
end

string(x::FreeSymbol) = string(x.name)

Base.:(==)(x::FreeSymbol, y::FreeSymbol) = x.name == y.name

hash(x::FreeSymbol) = hash(x.name)

##### Helpers

"""
Returns true iff the form cannot be further reduced and contains no immediate
evaluation. (Immediate evaluation just means evaluations that cannot be done yet
but must eventually be performed).
"""
reduced(form) = true
reduced(form::Immediate) = false
reduced(form::Application) = false
reduced(form::ds.Symbol) = false
reduced(form::Pair) = reduced(form.head) && reduced(form.tail)
reduced(form::Mu) = reduced(form.arg) && reduced(form.body)
reduced(form::ds.Vector) = ds.every(reduced, form)
reduced(form::ds.Map) = ds.every(reduced, form)
reduced(form::ds.MapEntry) = reduced(ds.key(form)) && reduced(ds.val(form))

### Debugging and inspection

function space(level)
  if level > 0
    print(repeat(" |", level))
  end
end

function inspect(form::Pair, level=0)
  space(level)
  println("P")
  inspect(form.head, level+1)
  inspect(form.tail, level+1)
end

function inspect(form::Immediate, level=0)
  space(level)
  println("I")
  inspect(form.form, level+1)
end

function inspect(form::LexicalSymbol, level=0)
  space(level)
  println("Sl["*string(form)*"]")
end

function inspect(form::FreeSymbol, level=0)
  space(level)
  println("Sf["*string(form)*"]")
end

function inspect(form::Application, level=0)
  space(level)
  println("A")
  inspect(form.head, level+1)
  inspect(form.tail, level+1)
end

function inspect(form::ds.Vector, level=0)
  space(level)
  println("L")
  for e in form
    inspect(e, level+1)
  end
end

function inspect(form::PartialMu, level=0)
  space(level)
  println("Pμ")
  inspect(form.arg, level+1)
  inspect(form.body, level+1)
end

function inspect(form::Mu, level=0)
  space(level)
  println("μ")
  inspect(form.arg, level+1)
  inspect(form.body, level+1)
end

function inspect(form::BuiltIn, level=0)
  space(level)
  println("F["*string(form)*"]")
end

function inspect(form, level=0)
  space(level)
  println("V["*string(typeof(form))*"]")
end

function inspect(form::TopLevel, level=0)
  space(level)
  println("-T-")
  inspect(form.form, level)
end

end # module
