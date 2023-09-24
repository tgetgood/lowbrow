@testset "maps" begin
  @test hashmap() === emptymap

  @test begin
    a = assoc(emptymap, :key, :value)
    get(a, :key) === :value
  end

  @test get(emptymap, :key, :default) === :default
end

@testset "ordered maps" begin
  # TODO:
end
