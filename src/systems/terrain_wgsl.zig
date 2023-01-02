// zig fmt: off
const common =
\\  struct DrawUniforms {
\\      object_to_world: mat4x4<f32>,
\\      basecolor_roughness: vec4<f32>,
\\  }
\\  @group(1) @binding(0) var<uniform> draw_uniforms: DrawUniforms;
\\
\\  struct FrameUniforms {
\\      world_to_clip: mat4x4<f32>,
\\      camera_position: vec3<f32>,
\\      time: f32,
\\      padding1: u32,
\\      padding2: u32,
\\      padding3: u32,
\\      light_count: u32,
\\      light_positions: array<vec4<f32>, 32>,
\\      light_radiances: array<vec4<f32>, 32>,
\\  }
\\  @group(0) @binding(0) var<uniform> frame_uniforms: FrameUniforms;
;
pub const vs = common ++
\\  struct VertexOut {
\\      @builtin(position) position_clip: vec4<f32>,
\\      @location(0) position: vec3<f32>,
\\      @location(1) normal: vec3<f32>,
\\  }
\\  @stage(vertex) fn main(
\\      @location(0) position: vec3<f32>,
\\      @location(1) normal: vec3<f32>,
\\      @builtin(vertex_index) vertex_index: u32,
\\  ) -> VertexOut {
\\      var output: VertexOut;
\\      output.position_clip = vec4(position, 1.0) * draw_uniforms.object_to_world * frame_uniforms.world_to_clip;
\\      output.position = (vec4(position, 1.0) * draw_uniforms.object_to_world).xyz;
\\       output.normal = normal;
\\      let index = vertex_index % 3u;
\\      return output;
\\  }
;
pub const fs = common ++
\\  let pi = 3.1415926;
\\
\\  fn saturate(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }
\\
\\  // Trowbridge-Reitz GGX normal distribution function.
\\  fn distributionGgx(n: vec3<f32>, h: vec3<f32>, alpha: f32) -> f32 {
\\      let alpha_sq = alpha * alpha;
\\      let n_dot_h = saturate(dot(n, h));
\\      let k = n_dot_h * n_dot_h * (alpha_sq - 1.0) + 1.0;
\\      return alpha_sq / (pi * k * k);
\\  }
\\
\\  fn geometrySchlickGgx(x: f32, k: f32) -> f32 {
\\      return x / (x * (1.0 - k) + k);
\\  }
\\
\\  fn geometrySmith(n: vec3<f32>, v: vec3<f32>, l: vec3<f32>, k: f32) -> f32 {
\\      let n_dot_v = saturate(dot(n, v));
\\      let n_dot_l = saturate(dot(n, l));
\\      return geometrySchlickGgx(n_dot_v, k) * geometrySchlickGgx(n_dot_l, k);
\\  }
\\
\\  fn fresnelSchlick(h_dot_v: f32, f0: vec3<f32>) -> vec3<f32> {
\\      return f0 + (vec3(1.0, 1.0, 1.0) - f0) * pow(1.0 - h_dot_v, 5.0);
\\  }
\\
\\  fn pointLight(light_index: u32, position: vec3<f32>, base_color: vec3<f32>, v: vec3<f32>, f0: vec3<f32>, n: vec3<f32>, alpha: f32, k: f32, metallic: f32) -> vec3<f32> {
\\          var lvec = frame_uniforms.light_positions[light_index].xyz - position;
\\         //  lvec.y += sin(frame_uniforms.time * 1.0) * 5.0;
\\
\\          let l = normalize(lvec);
\\          let h = normalize(l + v);
\\
\\          let lightData = frame_uniforms.light_radiances[light_index];
\\          let range = lightData.w;
\\          let range_sq = range * range;
\\          let distance_sq = dot(lvec, lvec);
\\          if (range_sq < distance_sq) {
\\              return vec3(0.0, 0.0, 0.0);
\\          }
\\
\\          // https://lisyarus.github.io/blog/graphics/2022/07/30/point-light-attenuation.html
\\          let distance = length(lvec);
\\          let attenuation_real = min(1.0, 1.0 / (1.0 + distance_sq));
\\          let attenuation_el = (distance_sq / range_sq ) * (2.0 * distance / range - 3.0) + 1.0;
\\          let attenuation_nik_s2 = distance_sq / range_sq;
\\          let attenuation_nik = (1.0 - attenuation_nik_s2) * (1.0 - attenuation_nik_s2) / (1.0 + 5.0 * attenuation_nik_s2);
\\          let attenuation = attenuation_nik;
\\          let variance = 1.0 + 0.2 * sin(frame_uniforms.time * 1.7);
\\          let radiance = lightData.xyz * attenuation * variance;
\\
\\          let f = fresnelSchlick(saturate(dot(h, v)), f0);
\\
\\          let ndf = distributionGgx(n, h, alpha);
\\          let g = geometrySmith(n, v, l, k);
\\
\\          let numerator = ndf * g * f;
\\          let denominator = 4.0 * saturate(dot(n, v)) * saturate(dot(n, l));
\\          let specular = numerator / max(denominator, 0.001);
\\
\\          let ks = f;
\\          let kd = (vec3(1.0) - ks) * (1.0 - metallic);
\\
\\          let n_dot_l = saturate(dot(n, l));
\\          // return base_color * radiance * n_dot_l;
\\          return (kd * base_color / pi + specular) * radiance * n_dot_l;
\\  }
\\
\\  @stage(fragment) fn main(
\\      @location(0) position: vec3<f32>,
\\      @location(1) normal: vec3<f32>,
\\  ) -> @location(0) vec4<f32> {
\\      let v = normalize(frame_uniforms.camera_position - position);
\\      let n = normalize(normal);
\\
\\      let colors = array<vec3<f32>, 5>(
\\          vec3(0.0, 0.1, 0.7),
\\          vec3(1.0, 1.0, 0.0),
\\          vec3(0.3, 0.8, 0.2),
\\          vec3(0.7, 0.7, 0.7),
\\          vec3(0.95, 0.95, 0.95),
\\      );

\\      var base_color = colors[0];
\\      base_color = mix(base_color, colors[1], step(0.005, position.y * 0.01));
\\      base_color = mix(base_color, colors[2], step(0.02, position.y * 0.01));
\\      base_color = mix(base_color, colors[3], step(1.0, position.y * 0.01 + 0.5 * (1.0 - dot(n, vec3(0.0, 1.0, 0.0))) ));
\\      base_color = mix(base_color, colors[4], step(3.5, position.y * 0.01 + 1.5 * dot(n, vec3(0.0, 1.0, 0.0)) ));
\\
\\
\\      let ao = 1.0;
\\      var roughness = draw_uniforms.basecolor_roughness.a;
\\      var metallic: f32;
\\      if (roughness < 0.0) { metallic = 1.0; } else { metallic = 0.0; }
\\      roughness = abs(roughness);
\\
\\      let alpha = roughness * roughness;
\\      var k = alpha + 1.0;
\\      k = (k * k) / 8.0;
\\      var f0 = vec3(0.04);
\\      f0 = mix(f0, base_color, metallic);
\\
\\      var lo = vec3(0.0);
\\      for (var light_index: u32 = 0u; light_index < frame_uniforms.light_count; light_index = light_index + 1u) {
\\          let lightContrib = pointLight(light_index, position, base_color, v, f0, n, alpha, k, metallic);
\\          lo += lightContrib;
\\      }
\\
\\      let sun_height = sin(frame_uniforms.time * 0.5);
\\      let sun_color = vec3(1.0, 0.914 * sun_height, 0.843 * sun_height * sun_height);
\\      let sun = max(0.0, sun_height) * 0.3 * base_color * (0.0 + saturate(dot(n, normalize(sun_color))));
\\      let sun2 = 0.5 * base_color * saturate(dot(n, normalize( vec3(0.0, 1.0, 0.0))));
\\
\\      let ambient_day   = vec3(0.0002 * saturate(sun_height + 0.1)) * vec3(0.9, 0.9, 1.0) * base_color;
\\      let ambient_night = vec3(0.05 * saturate(sign(-sun_height + 0.1))) * vec3(0.2, 0.2, 1.0) * base_color;
\\      let ambient = (ambient_day + ambient_night) * ao * saturate(dot(n, vec3(0.0, 1.0, 0.0)));
\\      let fog_dist = length(position - frame_uniforms.camera_position);
\\      let fog_start = 500.0;
\\      let fog_end = 2500.0;
\\      let fog = saturate((fog_dist - fog_start) / (fog_end - fog_start));
\\      var color = ambient + lo + sun;
\\      color = mix(color, vec3(0.5, 0.5, 0.4), 1.0 * saturate(fog * fog * max(0.0, sun_height)));
\\      color = pow(color, vec3(1.0 / 2.2));
\\      // let n_xz = vec3(n.x, 0.0, n.z);
\\      // return vec4((n_xz), 1.0);
\\      // return vec4(10.0*sun, 1.0);
\\      // return vec4(lo, 1.0);
\\      // return vec4((n + 1.0) * 0.5, 1.0);
\\      return vec4(color, 1.0);
\\  }
// zig fmt: on
;
