// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import CoreImage
import Metal
import simd

/// Compiles lightweight GPU kernels from embedded Metal source at runtime via
/// `makeLibrary(source:)` so hosts without the offline `metallib` CLI still run
/// hardware-accelerated TPDF gradient dithering and directional motion blur,
/// falling back gracefully to CPU/CoreImage when Metal is unavailable.
final class VorssaintMetalShaders: @unchecked Sendable {
    static let shared = VorssaintMetalShaders()

    private let lock = NSLock()
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let library: MTLLibrary?
    private var ditherPipeline: MTLComputePipelineState?
    private var motionBlurPipeline: MTLComputePipelineState?

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct DitherUniforms {
        float4 startColor;
        float4 endColor;
        float2 size;
        float amplitude;
    };

    inline float hash21(uint2 p) {
        uint n = p.x * 374761393u + p.y * 668265263u;
        n = (n ^ (n >> 13u)) * 1274126177u;
        return float(n ^ (n >> 16u)) / 4294967295.0f;
    }

    kernel void ditherGradient(texture2d<float, access::write> outTex [[texture(0)]],
                               constant DitherUniforms &u [[buffer(0)]],
                               uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= uint(u.size.x) || gid.y >= uint(u.size.y)) { return; }
        float nx = u.size.x > 1.0f ? float(gid.x) / (u.size.x - 1.0f) : 0.0f;
        float ny = u.size.y > 1.0f ? float(gid.y) / (u.size.y - 1.0f) : 0.0f;
        // Diagonal bottom-left to top-right matching ScreenshotRenderer CGContext coordinates.
        float t = clamp((nx + ny) * 0.5f, 0.0f, 1.0f);
        float4 col = mix(u.startColor, u.endColor, t);
        // Triangular probability density function noise (+/- amplitude LSB).
        float n1 = hash21(gid);
        float n2 = hash21(gid + uint2(17u, 53u));
        float tpdf = (n1 - n2) * u.amplitude;
        col.rgb = clamp(col.rgb + float3(tpdf), 0.0f, 1.0f);
        outTex.write(float4(col.rgb, 1.0f), gid);
    }

    struct MotionBlurUniforms {
        float2 velocity;
        float2 size;
        int samples;
    };

    kernel void directionalMotionBlur(texture2d<float, access::sample> inTex [[texture(0)]],
                                      texture2d<float, access::write> outTex [[texture(1)]],
                                      constant MotionBlurUniforms &u [[buffer(0)]],
                                      uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= uint(u.size.x) || gid.y >= uint(u.size.y)) { return; }
        constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
        float2 uv = (float2(gid) + 0.5f) / u.size;
        int count = max(1, u.samples);
        float4 accum = float4(0.0f);
        for (int i = 0; i < count; ++i) {
            float offset = (float(i) / max(1.0f, float(count - 1))) - 0.5f;
            float2 sampleUV = uv + u.velocity * offset;
            accum += inTex.sample(s, sampleUV);
        }
        outTex.write(accum / float(count), gid);
    }
    """

    private init() {
        let dev = MTLCreateSystemDefaultDevice()
        self.device = dev
        self.commandQueue = dev?.makeCommandQueue()
        self.library = try? dev?.makeLibrary(source: Self.shaderSource, options: nil)
    }

    var isMetalAvailable: Bool {
        device != nil && commandQueue != nil && library != nil
    }

    private func ensureDitherPipeline() -> MTLComputePipelineState? {
        lock.lock()
        defer { lock.unlock() }
        if let ditherPipeline { return ditherPipeline }
        guard let fn = library?.makeFunction(name: "ditherGradient"),
              let pipeline = try? device?.makeComputePipelineState(function: fn) else {
            return nil
        }
        ditherPipeline = pipeline
        return pipeline
    }

    private func ensureMotionBlurPipeline() -> MTLComputePipelineState? {
        lock.lock()
        defer { lock.unlock() }
        if let motionBlurPipeline { return motionBlurPipeline }
        guard let fn = library?.makeFunction(name: "directionalMotionBlur"),
              let pipeline = try? device?.makeComputePipelineState(function: fn) else {
            return nil
        }
        motionBlurPipeline = pipeline
        return pipeline
    }

    private struct DitherUniforms {
        var startColor: SIMD4<Float>
        var endColor: SIMD4<Float>
        var size: SIMD2<Float>
        var amplitude: Float
    }

    private struct MotionBlurUniforms {
        var velocity: SIMD2<Float>
        var size: SIMD2<Float>
        var samples: Int32
    }

    /// Renders a band-free TPDF-dithered gradient image onto `size` pixels.
    func makeDitheredGradientImage(width: Int,
                                   height: Int,
                                   start: (red: Double, green: Double, blue: Double),
                                   end: (red: Double, green: Double, blue: Double)) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        if let device,
           let queue = commandQueue,
           let pipeline = ensureDitherPipeline(),
           let img = renderMetalDitherGradient(device: device, queue: queue, pipeline: pipeline,
                                               width: width, height: height, start: start, end: end) {
            return img
        }
        return nil
    }

    private func renderMetalDitherGradient(device: MTLDevice,
                                           queue: MTLCommandQueue,
                                           pipeline: MTLComputePipelineState,
                                           width: Int,
                                           height: Int,
                                           start: (red: Double, green: Double, blue: Double),
                                           end: (red: Double, green: Double, blue: Double)) -> CGImage? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderWrite, .shaderRead]
        guard let tex = device.makeTexture(descriptor: desc),
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else {
            return nil
        }
        var uniforms = DitherUniforms(
            startColor: SIMD4<Float>(Float(start.red), Float(start.green), Float(start.blue), 1),
            endColor: SIMD4<Float>(Float(end.red), Float(end.green), Float(end.blue), 1),
            size: SIMD2<Float>(Float(width), Float(height)),
            amplitude: 1.5 / 255.0
        )
        enc.setComputePipelineState(pipeline)
        enc.setTexture(tex, index: 0)
        enc.setBytes(&uniforms, length: MemoryLayout<DitherUniforms>.stride, index: 0)
        let w = pipeline.threadExecutionWidth
        let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
        let tg = MTLSize(width: w, height: h, depth: 1)
        let grid = MTLSize(width: width, height: height, depth: 1)
        enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { return nil }

        let bytesPerRow = width * 4
        var buffer = Data(count: bytesPerRow * height)
        buffer.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            tex.getBytes(base, bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: buffer as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Applies directional motion blur for camera pans & zoom transitions.
    /// Automatically falls back to CoreImage `CIMotionBlur` if Metal is absent.
    func applyDirectionalMotionBlur(to image: CIImage,
                                    velocity: CGVector,
                                    samples: Int = 9) -> CIImage {
        let magnitude = hypot(velocity.dx, velocity.dy)
        guard magnitude > 0.5 else { return image }
        let extent = image.extent
        let w = Int(extent.width.rounded())
        let h = Int(extent.height.rounded())
        if let device,
           let queue = commandQueue,
           let pipeline = ensureMotionBlurPipeline(),
           w > 0, h > 0, w <= 8192, h <= 8192,
           let ciContext = CIContext(mtlDevice: device) as CIContext?,
           let blurred = renderMetalMotionBlur(image: image, extent: extent, width: w, height: h,
                                               velocity: velocity, samples: samples,
                                               device: device, queue: queue,
                                               pipeline: pipeline, context: ciContext) {
            return blurred
        }
        guard let filter = CIFilter(name: "CIMotionBlur") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(min(40.0, Double(magnitude)), forKey: kCIInputRadiusKey)
        filter.setValue(Double(atan2(velocity.dy, velocity.dx)), forKey: kCIInputAngleKey)
        return filter.outputImage?.cropped(to: extent) ?? image
    }

    private func renderMetalMotionBlur(image: CIImage,
                                       extent: CGRect,
                                       width: Int,
                                       height: Int,
                                       velocity: CGVector,
                                       samples: Int,
                                       device: MTLDevice,
                                       queue: MTLCommandQueue,
                                       pipeline: MTLComputePipelineState,
                                       context: CIContext) -> CIImage? {
        let inDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        inDesc.usage = [.shaderRead, .shaderWrite]
        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        outDesc.usage = [.shaderWrite, .shaderRead]
        guard let inTex = device.makeTexture(descriptor: inDesc),
              let outTex = device.makeTexture(descriptor: outDesc),
              let cmd = queue.makeCommandBuffer() else { return nil }

        let shifted = image.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
        context.render(shifted, to: inTex, commandBuffer: cmd,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       colorSpace: CGColorSpaceCreateDeviceRGB())
        guard let enc = cmd.makeComputeCommandEncoder() else { return nil }
        let normV = SIMD2<Float>(Float(velocity.dx) / Float(max(1, width)),
                                 Float(velocity.dy) / Float(max(1, height)))
        var uniforms = MotionBlurUniforms(
            velocity: normV,
            size: SIMD2<Float>(Float(width), Float(height)),
            samples: Int32(max(3, min(15, samples)))
        )
        enc.setComputePipelineState(pipeline)
        enc.setTexture(inTex, index: 0)
        enc.setTexture(outTex, index: 1)
        enc.setBytes(&uniforms, length: MemoryLayout<MotionBlurUniforms>.stride, index: 0)
        let tw = pipeline.threadExecutionWidth
        let th = max(1, pipeline.maxTotalThreadsPerThreadgroup / tw)
        enc.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1))
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed,
              let outImage = CIImage(mtlTexture: outTex, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]) else {
            return nil
        }
        return outImage
            .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
            .cropped(to: extent)
    }
}
