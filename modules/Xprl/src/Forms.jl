module Forms

import DataStructures as ds

abstract type Form end

struct ListForm <: Form
  env::ds.Map
  head::Any
  tail::ds.Vector
end

struct ValueForm <: Form
  env::ds.Map
  content::Any
end

end
