# Shameless ripoff of Stuart Sierra's walk in clojure.

function walk(inner, outer, form::Pair)
  outer(Pair(inner(form.head), inner(form.tail)))
end

function walk(inner, outer, form::Sequential)
  outer(into(empty(form), map(inner), form))
end

function walk(inner, outer, e::MapEntry)
  outer(MapEntry(inner(e.key), inner(e.value)))
end

function walk(inner, outer, f::Immediate)
  outer(Immediate(inner(f.content)))
end

function walk(inner, outer, l::ArgList)
  outer(ArgList(into(emptyvector, map(inner), l.contents)))
end

function walk(inner, outer, v)
  outer(v)
end

function postwalk(f, form)
  walk(x -> postwalk(f, x), f, form)
end

function prewalk(f, form)
  walk(x -> prewalk(f, x), identity, f(form))
end
