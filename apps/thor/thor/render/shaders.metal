#include <metal_stdlib>
using namespace metal;

struct Instance {
    float4 rect;
    float4 uv;
    float4 color;
    float4 border_color;
    float4 clip;
    float4 corner_radius;
    float border_width;
    float softness;
    uint kind;
    float layer_opacity;
    float4 end_color;
    float2 gradient;
    float rotation;
    uint gradient_kind;
    float4 under_color;
    uint layer_first;
    uint layer_count;
    uint2 reserved;
};

constant uint layer_gradient = 1;
constant uint layer_texture = 2;
constant uint layer_surface = 3;

struct Layer {
    uint kind;
    uint blend;
    uint is_tiled;
    float amount;
    float4 from;
    float4 to;
    float4 shape;
    float4 uv;
};

// What the target holds: linear or gamma, sRGB or Display P3.
constant uint color_linear = 1;
constant uint color_p3 = 2;

// The sRGB curve, kept odd so a P3 color outside sRGB, with a negative channel, survives.
float3 to_linear(float3 c) {
    float3 a = abs(c);
    return sign(c) * select(pow((a + 0.055) / 1.055, 2.4), a / 12.92, a <= 0.04045);
}

float3 to_gamma(float3 c) {
    float3 a = abs(c);
    return sign(c) * select(1.055 * pow(a, 1.0 / 2.4) - 0.055, a * 12.92, a <= 0.0031308);
}

float to_linear(float c) { return to_linear(float3(c)).x; }
float to_gamma(float c) { return to_gamma(float3(c)).x; }

// Linear sRGB to linear Display P3, both D65. Display P3 uses the sRGB curve.
constant float3x3 srgb_to_p3 = float3x3(
    float3(0.8224621, 0.0331941, 0.0170827),
    float3(0.1775380, 0.9668058, 0.0723974),
    float3(0.0, 0.0, 0.9105199)
);

float3 to_target(float3 srgb, uint flags) {
    if (flags == 0) return srgb;
    float3 c = to_linear(srgb);
    if ((flags & color_p3) != 0) c = srgb_to_p3 * c;
    return (flags & color_linear) != 0 ? c : to_gamma(c);
}

float4 to_target(float4 srgb, uint flags) {
    return float4(to_target(srgb.rgb, flags), srgb.a);
}

float to_luminance(float3 linear) {
    return dot(linear, float3(0.2126, 0.7152, 0.0722));
}

constant uint gradient_across = 1;
constant uint gradient_linear = 2;

float to_gradient_step(Instance instance, float2 point) {
    float along = (instance.gradient_kind & gradient_across) != 0
        ? (point.x - instance.rect.x) / (instance.rect.z - instance.rect.x)
        : (point.y - instance.rect.y) / (instance.rect.w - instance.rect.y);
    if ((instance.gradient_kind & gradient_linear) != 0) {
        return clamp((along - instance.gradient.x) / (instance.gradient.y - instance.gradient.x), 0.0, 1.0);
    }
    return smoothstep(instance.gradient.x, instance.gradient.y, along);
}

constant uint kind_glyph = 1;
constant uint kind_image = 2;
constant uint kind_shadow = 3;

struct Fragment {
    float4 position [[position]];
    float2 point;
    float2 uv;
    uint instance [[flat]];
};

float2 to_turned(float2 point, float2 center, float angle) {
    float2 offset = point - center;
    float s = sin(angle);
    float c = cos(angle);
    return center + float2(offset.x * c - offset.y * s, offset.x * s + offset.y * c);
}

vertex Fragment vertex_main(
    uint vertex_id [[vertex_id]],
    uint instance_id [[instance_id]],
    const device Instance *instances [[buffer(0)]],
    constant float2 &viewport [[buffer(1)]]
) {
    Instance instance = instances[instance_id];
    float2 corner = float2(vertex_id & 1, vertex_id >> 1);
    // Three standard deviations hold all of a shadow's blur.
    float padding = instance.kind == kind_glyph ? 0.0 : instance.kind == kind_shadow ? instance.softness * 1.5 + 1.0 : instance.softness + 1.0;
    float2 point = mix(instance.rect.xy - padding, instance.rect.zw + padding, corner);
    float2 along = (point - instance.rect.xy) / (instance.rect.zw - instance.rect.xy);
    // A turned rect's corners turn with it, so the fragment turns its point back.
    if (instance.rotation != 0.0) point = to_turned(point, (instance.rect.xy + instance.rect.zw) * 0.5, instance.rotation);

    Fragment output;
    output.position = float4(point / viewport * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    output.point = point;
    output.uv = mix(instance.uv.xy, instance.uv.zw, along);
    output.instance = instance_id;
    return output;
}

// The radius of the corner nearest offset, which is measured from the box's center.
float to_corner_radius(float2 offset, float4 radii) {
    return offset.y < 0.0 ? (offset.x < 0.0 ? radii.x : radii.y) : (offset.x < 0.0 ? radii.w : radii.z);
}

// Evan Wallace's closed-form Gaussian blur of a rounded rect, right for any blur on any size.
float to_gaussian(float x, float sigma) {
    return exp(-(x * x) / (2.0 * sigma * sigma)) / (2.5066283 * sigma);
}

float2 to_erf(float2 x) {
    float2 s = sign(x), a = abs(x);
    x = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;
    x *= x;
    return s - s / (x * x);
}

float to_shadow_row(float x, float y, float sigma, float corner, float2 half_size) {
    float delta = min(half_size.y - corner - abs(y), 0.0);
    float curved = half_size.x - corner + sqrt(max(0.0, corner * corner - delta * delta));
    float2 integral = 0.5 + 0.5 * to_erf((x + float2(-curved, curved)) * (0.70710678 / sigma));
    return integral.y - integral.x;
}

float to_shadow(float2 offset, float2 half_size, float sigma, float corner) {
    float start = clamp(-3.0 * sigma, offset.y - half_size.y, offset.y + half_size.y);
    float end = clamp(3.0 * sigma, offset.y - half_size.y, offset.y + half_size.y);
    float step = (end - start) / 4.0;
    float y = start + step * 0.5;
    float value = 0.0;
    for (int i = 0; i < 4; i++) {
        value += to_shadow_row(offset.x, offset.y - y, sigma, corner, half_size) * to_gaussian(y, sigma) * step;
        y += step;
    }
    return value;
}

// W3C's separable blend modes, on straight colors.
float3 to_blend(float3 below, float3 source, uint mode) {
    switch (mode) {
    case 1:
        return below * source;
    case 2:
        return below + source - below * source;
    case 3:
        return select(1.0 - 2.0 * (1.0 - below) * (1.0 - source), 2.0 * below * source, below <= 0.5);
    case 4: {
        float3 lift = select(sqrt(below), ((16.0 * below - 12.0) * below + 4.0) * below, below <= 0.25);
        return select(below + (2.0 * source - 1.0) * (lift - below), below - (1.0 - 2.0 * source) * below * (1.0 - below), source <= 0.5);
    }
    default:
        return source;
    }
}

// Source over a premultiplied color with a blend mode, as W3C's compositing spec defines it.
float4 to_blended(float4 below, float3 source, float alpha, uint mode) {
    float3 straight = below.a > 0.0 ? below.rgb / below.a : float3(0.0);
    float3 mixed = (1.0 - below.a) * source + below.a * to_blend(straight, source, mode);
    return float4(alpha * mixed + (1.0 - alpha) * below.rgb, alpha + below.a * (1.0 - alpha));
}

float2 to_layer_uv(Layer layer, Instance instance, float2 point) {
    float2 along = point - instance.rect.xy;
    if (layer.is_tiled != 0) return along / layer.uv.xy;
    return mix(layer.uv.xy, layer.uv.zw, along / (instance.rect.zw - instance.rect.xy));
}

float4 to_layer_sample(texture2d<float> image, sampler fill, sampler tile, Layer layer, float2 uv) {
    return layer.is_tiled != 0 ? image.sample(tile, uv) : image.sample(fill, uv);
}

float to_height(texture2d<float> image, sampler fill, sampler tile, Layer layer, float2 uv) {
    return dot(to_layer_sample(image, fill, tile, layer, uv).rgb, float3(0.2126, 0.7152, 0.0722));
}

float4 to_layered(float4 below, Layer layer, texture2d<float> image, sampler fill, sampler tile, Instance instance, float2 point, uint flags) {
    float opacity = instance.layer_opacity;

    if (layer.kind == layer_gradient) {
        float2 direction = float2(sin(layer.shape.z), cos(layer.shape.z));
        float2 half_size = (instance.rect.zw - instance.rect.xy) * 0.5;
        float reach = abs(half_size.x * direction.x) + abs(half_size.y * direction.y);
        float along = 0.5 + dot(point - (instance.rect.xy + instance.rect.zw) * 0.5, direction) / (2.0 * reach);
        float4 color = mix(to_target(layer.from, flags), to_target(layer.to, flags), smoothstep(layer.shape.x, layer.shape.y, along));
        return to_blended(below, color.rgb, color.a * opacity, 0);
    }

    float2 uv = to_layer_uv(layer, instance, point);

    if (layer.kind == layer_texture) {
        float4 pixel = to_layer_sample(image, fill, tile, layer, uv);
        float3 source = pixel.a > 0.0 ? to_target(pixel.rgb / pixel.a, flags) : float3(0.0);
        return to_blended(below, source, pixel.a * layer.amount * opacity, layer.blend);
    }

    // A surface: the height map's slope, per pixel, lit from shape.z at 45 degrees up.
    float2 texel = 1.0 / float2(image.get_width(), image.get_height());
    float2 texel_pixels = layer.is_tiled != 0 ? layer.uv.xy * texel : (instance.rect.zw - instance.rect.xy) / (layer.uv.zw - layer.uv.xy) * texel;
    float2 slope = float2(
        to_height(image, fill, tile, layer, uv + float2(texel.x, 0.0)) - to_height(image, fill, tile, layer, uv - float2(texel.x, 0.0)),
        to_height(image, fill, tile, layer, uv + float2(0.0, texel.y)) - to_height(image, fill, tile, layer, uv - float2(0.0, texel.y))
    ) * layer.amount / (2.0 * texel_pixels);
    float3 normal = normalize(float3(-slope, 1.0));
    float up = 0.70710678;
    float lit = dot(normal, float3(sin(layer.shape.z) * up, -cos(layer.shape.z) * up, up)) - up;
    float shade = (lit > 0.0 ? lit / (1.0 - up) : lit / up) * opacity;
    float3 straight = below.a > 0.0 ? below.rgb / below.a : float3(0.0);
    float4 light = to_target(layer.from, flags);
    straight = shade > 0.0 ? mix(straight, light.rgb, min(shade, 1.0) * light.a) : straight * max(0.0, 1.0 + shade);
    return float4(straight * below.a, below.a);
}

// Inigo Quilez's signed distance function for a rounded box.
float to_box_distance(float2 point, float2 half_size, float radius) {
    float2 q = abs(point) - half_size + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

fragment float4 fragment_main(
    Fragment input [[stage_in]],
    const device Instance *instances [[buffer(0)]],
    texture2d<float> image [[texture(0)]],
    sampler texture_sampler [[sampler(0)]],
    constant uint &flags [[buffer(1)]],
    const device Layer *layers [[buffer(2)]],
    array<texture2d<float>, 4> layer_textures [[texture(1)]],
    sampler tile_sampler [[sampler(1)]]
) {
    Instance instance = instances[input.instance];
    float2 point = input.point;

    if (any(point < instance.clip.xy) || any(point > instance.clip.zw)) discard_fragment();
    if (instance.rotation != 0.0) point = to_turned(point, (instance.rect.xy + instance.rect.zw) * 0.5, -instance.rotation);

    if (instance.kind == kind_glyph) {
        float coverage = image.sample(texture_sampler, input.uv).r;
        float3 rgb = to_target(instance.color.rgb, flags);
        // Ghostty's correction: blend the luminances as gamma would, then find the coverage that
        // gives that luminance in linear light, so text keeps its weight.
        if ((flags & color_linear) != 0 && instance.under_color.a > 0.0) {
            float fg = to_luminance(rgb);
            float bg = to_luminance(to_target(instance.under_color.rgb, flags));
            if (abs(fg - bg) > 0.001) {
                float blend = to_linear(to_gamma(fg) * coverage + to_gamma(bg) * (1.0 - coverage));
                coverage = clamp((blend - bg) / (fg - bg), 0.0, 1.0);
            }
        }
        return float4(rgb, 1.0) * instance.color.a * coverage;
    }

    float2 half_size = (instance.rect.zw - instance.rect.xy) * 0.5;
    float2 center = (instance.rect.xy + instance.rect.zw) * 0.5;

    if (instance.kind == kind_shadow) {
        float2 offset = point - center;
        float corner = min(to_corner_radius(offset, instance.corner_radius), min(half_size.x, half_size.y));
        float4 color = to_target(instance.color, flags);
        return float4(color.rgb * color.a, color.a) * to_shadow(offset, half_size, max(instance.softness * 0.5, 0.5), corner);
    }

    float radius = min(to_corner_radius(point - center, instance.corner_radius), min(half_size.x, half_size.y));
    float distance = to_box_distance(point - center, half_size, radius);
    float softness = max(instance.softness, 1.0);
    float coverage = 1.0 - smoothstep(-softness * 0.5, softness * 0.5, distance);
    bool has_gradient = instance.gradient.y > instance.gradient.x;

    if (instance.kind == kind_image) {
        float4 pixel = image.sample(texture_sampler, input.uv);
        if (pixel.a > 0.0) pixel.rgb = to_target(pixel.rgb / pixel.a, flags) * pixel.a;
        float fade = 1.0;

        if (has_gradient) {
            fade = 1.0 - to_gradient_step(instance, point);
        }

        return pixel * float4(to_target(instance.color.rgb, flags), 1.0) * instance.color.a * coverage * fade;
    }

    float4 color = to_target(instance.color, flags);

    if (has_gradient) {
        color = mix(color, to_target(instance.end_color, flags), to_gradient_step(instance, point));
    }

    // Premultiplied, with the border over the fill: a translucent border tints the fill below it,
    // and its anti-aliased edge blends without a lighter or darker fringe.
    float4 fill = float4(color.rgb * color.a, color.a);
    for (uint slot = 0; slot < instance.layer_count; slot++) {
        fill = to_layered(fill, layers[instance.layer_first + slot], layer_textures[slot], texture_sampler, tile_sampler, instance, point, flags);
    }

    if (instance.border_width > 0.0) {
        float border = smoothstep(-0.5, 0.5, distance + instance.border_width);
        float4 edge = float4(to_target(instance.border_color.rgb, flags), 1.0) * instance.border_color.a * border;
        fill = edge + fill * (1.0 - edge.a);
    }

    return fill * coverage;
}
