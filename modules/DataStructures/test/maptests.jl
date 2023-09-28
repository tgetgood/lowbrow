@testset "array maps" begin
  @test hashmap() === emptymap

  @test begin
    a = assoc(emptymap, :key, :value)
    get(a, :key) === :value
  end

  @test get(emptymap, :key, :default) === :default

  c = hashmap(
    :key, 1,
    "string", complex(1f0, 13f-2),
    [1,2,3], Base.Vector,
    vector(1, 2, 3), Vector
  )

  @test get(c, [1,2,3]) === Base.Vector
  @test get(c, vec(1:3)) === Vector
  @test get(c, "string") === complex(1f0, 13f-2)
end

@testset "nested maps" begin
  m = hashmap(:a, hashmap(:b, 5))

  @test getin(m, [:a, :b]) === 5
  @test getin(m, [:a, :a], :default) === :default
  @test getin(m, [:b, :a], :default) === :default

  @test getin(updatein(m, [:a, :b], x -> x + 1), [:a, :b]) == 6
  @test getin(associn(m, [:a, :c, :b], :sym), [:a, :c]) == hashmap(:b, :sym)

  m2 = into(emptymap, map(i -> (i,i)), 1:4)

  m3 = merge(m, m2)

  @test count(m3) == count(m) + count(m2)

  @test get(m3, 2) == 2
  @test getin(m3, [:a, :b]) == 5

  @test_throws MethodError updatein(m3, [1, :c], conj, "purple")

  m4 = updatein(m3, [:a, :c], conj, "purple")

  @test count(m4) == count(m3)
  @test count(get(m4, :a)) == count(get(m3, :a)) + 1

  @info m4
  @test getin(m4, [:a, :c]) == vector("purple")
end

@testset "hash maps" begin
  @test get(assoc(assoc(emptyhashmap, :a, 6), :a, 2), :a) == 2

  c = reduce(
    conj,
    emptyhashmap,
    [(:key, 1),
    ("string", complex(1f0, 13f-2)),
     ([1,2,3], Base.Vector),
    (vector(1, 2, 3), assoc(emptyhashmap, :some, "string"))]
  )

  @test get(c, [1,2,3]) === Base.Vector
  @test get(c, "string") === complex(1f0, 13f-2)
  @test getin(c, [vec(1:3), :some]) == "string"

  m = into(emptymap, map(i -> (i, i)), 1:2*arraymapsizethreashold)

  @test m isa ds.PersistentHashMap

  @test count(merge(m, c)) == 2*arraymapsizethreashold + 4
  @test get(m, 443) == nothing
  @test get(m, arraymapsizethreashold) == arraymapsizethreashold

  @test get(assoc(m, "string", vector(:a, 2, "c")), "string") isa Vector
end

@testset "merging maps" begin
  a = hashmap(
    :test, 1,
    :key, 2
  )

  b = hashmap(
    "test", 1,
    :key, 4
  )

  c = merge(a, b)

  @test count(c) < count(a) + count(b)
  @test get(c, :key) == 4
  @test get(merge(b, a), :key) == 2
end

@testset "ordered maps" begin
  # TODO:
end
