#version 450

struct Pixel {
  uint done;
  uint count;
  vec2 mu;
  vec2 z;
};

// layout(binding = 0) uniform sampler2D sam;

layout(push_constant) uniform constants {
  uvec2 window;
  uint count;
} pcs;

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 outColour;

layout(std140, binding = 0) readonly restrict buffer PixelSSBOIn {
   Pixel pixels[ ];
};

uint hash( uint x ) {
    x += ( x << 10u );
    x ^= ( x >>  6u );
    x += ( x <<  3u );
    x ^= ( x >> 11u );
    x += ( x << 15u );
    return x;
}



// Compound versions of the hashing algorithm I whipped together.
uint hash( uvec2 v ) { return hash( v.x ^ hash(v.y)                         ); }
uint hash( uvec3 v ) { return hash( v.x ^ hash(v.y) ^ hash(v.z)             ); }
uint hash( uvec4 v ) { return hash( v.x ^ hash(v.y) ^ hash(v.z) ^ hash(v.w) ); }



// Construct a float with half-open range [0:1] using low 23 bits.
// All zeroes yields 0.0, all ones yields the next smallest representable value below 1.0.
float floatConstruct( uint m ) {
    const uint ieeeMantissa = 0x007FFFFFu; // binary32 mantissa bitmask
    const uint ieeeOne      = 0x3F800000u; // 1.0 in IEEE binary32

    m &= ieeeMantissa;                     // Keep only mantissa bits (fractional part)
    m |= ieeeOne;                          // Add fractional part to 1.0

    float  f = uintBitsToFloat( m );       // Range [1:2]
    return f - 1.0;                        // Range [0:1]
}

void main() {
  // outColour = vec4(texture(sam, texCoord).rgb, 1.0);
  // outColour = vec4(texCoord, 1.0, 1.0);
  uint i = uint(gl_FragCoord.x - 0.5);
  uint j = uint(gl_FragCoord.y - 0.5);

  // if (i < j) {
  //   discard;
  // }

  uint n = i + j * pcs.window[0];
  uint N = pcs.window[0] * pcs.window[1];

  // if (n >= N) {
  //   discard;
  // } else {
    Pixel p = pixels[n];
  
    uint c = pixels[n].count;
    // uint c = pcs.count;

    // if (c < 100000) {
    //   discard;
    // }

    // float r = float(c>>8)/15.0;
    // float g = float((c&((1<<8)-1))>>4)/15.0;
    // float b = float(c&15)/15.0;

    // outColour = vec4(pixels[n].mu, 0.0, 1.0);
    outColour = vec4(0.0, 0.0, floatConstruct(c), 1.0);
    // outColour = vec4(r,g,b, 1.0);
  // }
}
