@testset "maps" begin
  @test hashmap() === emptymap

  @test begin
    a = assoc(emptymap, :key, :value)
    get(a, :key) === :value && get(a, :key2, :default) === :default
  end
end
