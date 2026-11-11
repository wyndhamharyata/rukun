#include <metal_stdlib>
using namespace metal;

struct Instance {
    float4 rect;
    float4 uv;
    float4 color;
    float4 border_color;
    float4 clip;
    float corner_radius;
    float border_width;
    float softness;
    uint kind;
    float4 end_color;
    float2 gradient;
    float rotation;
    uint gradient_kind;
    float4 under_color;
};

// What the target stores: linear light or gamma, and sRGB or Display P3.
constant uint color_linear = 1;
constant uint color_p3 = 2;

// The sRGB curve, kept odd so a P3 colour outside sRGB, which has a negative channel, survives.
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

// Linear sRGB to linear Display P3, both D65. Display P3 has the sRGB curve.
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
    float padding = instance.kind == kind_glyph ? 0.0 : instance.softness + 1.0;
    float2 point = mix(instance.rect.xy - padding, instance.rect.zw + padding, corner);
    float2 along = (point - instance.rect.xy) / (instance.rect.zw - instance.rect.xy);
    // A turned rect's corners turn with it; the fragment turns its point back.
    if (instance.rotation != 0.0) point = to_turned(point, (instance.rect.xy + instance.rect.zw) * 0.5, instance.rotation);

    Fragment output;
    output.position = float4(point / viewport * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    output.point = point;
    output.uv = mix(instance.uv.xy, instance.uv.zw, along);
    output.instance = instance_id;
    return output;
}

// Inigo Quilez's signed distance to a rounded box.
float to_box_distance(float2 point, float2 half_size, float radius) {
    float2 q = abs(point) - half_size + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

fragment float4 fragment_main(
    Fragment input [[stage_in]],
    const device Instance *instances [[buffer(0)]],
    texture2d<float> image [[texture(0)]],
    sampler texture_sampler [[sampler(0)]],
    constant uint &flags [[buffer(1)]]
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
    float radius = min(instance.corner_radius, min(half_size.x, half_size.y));
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

    // Premultiplied, and the border over the fill: a translucent border tints the fill beneath it,
    // and its anti-aliased edge blends without a lighter or darker fringe.
    float4 fill = float4(color.rgb * color.a, color.a);

    if (instance.border_width > 0.0) {
        float border = smoothstep(-0.5, 0.5, distance + instance.border_width);
        float4 edge = float4(to_target(instance.border_color.rgb, flags), 1.0) * instance.border_color.a * border;
        fill = edge + fill * (1.0 - edge.a);
    }

    return fill * coverage;
}
