@testset "small maps" begin
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
end

@testset "bigger maps" begin

  c = hashmap(
    :key, 1,
    "string", complex(1f0, 13f-2),
    [1,2,3], Base.Vector,
    vector(1, 2, 3), Vector
  )
  m = into(emptymap, map(i -> (i, i)), 1:nodelength)

  @test count(merge(m, c)) == nodelength + 4
  @test get(m, 443) == nothing
  @test get(m, 21) == 21

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
