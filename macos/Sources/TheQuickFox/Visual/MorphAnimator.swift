import Cocoa
import Metal
import MetalKit
import QuartzCore

final class MorphAnimator {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let renderPipelineState: MTLRenderPipelineState
    private var displayLink: CVDisplayLink?
    private var startTime: CFTimeInterval = 0
    private var duration: TimeInterval = 2.0

    private var startFrame: NSRect = .zero
    private var endFrame: NSRect = .zero
    private var animatingWindow: NSWindow?

    private var onUpdate: ((CGFloat) -> Void)?
    private var onComplete: (() -> Void)?

    // Metal rendering pipeline
    private var metalLayer: CAMetalLayer?
    private var cachedDrawableSize: CGSize = .zero

    struct Uniforms {
        var progress: Float
        var startSize: SIMD2<Float>
        var endSize: SIMD2<Float>
        var startPosition: SIMD2<Float>
        var endPosition: SIMD2<Float>
    }

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            print("❌ Metal device or command queue creation failed")
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue

        // Load Metal shader source from bundle
        // Resources are copied to Bundle.main by the build script
        guard let shaderURL = Bundle.main.url(forResource: "MorphShader", withExtension: "metal") else {
            print("❌ Failed to locate Metal shader in bundle")
            print("   Searched in: \(Bundle.main.bundlePath)")
            return nil
        }

        guard let shaderSource = try? String(contentsOf: shaderURL) else {
            print("❌ Failed to load Metal shader source file at: \(shaderURL.path)")
            return nil
        }

        print("✅ Found Metal shader at: \(shaderURL.path)")

        // Compile shader at runtime
        guard let library = try? device.makeLibrary(source: shaderSource, options: nil) else {
            print("❌ Failed to compile Metal shader library")
            return nil
        }

        guard let vertexFunction = library.makeFunction(name: "rainbowBorderVertex"),
              let fragmentFunction = library.makeFunction(name: "rainbowBorderFragment") else {
            print("❌ Failed to load vertex/fragment functions")
            return nil
        }

        // Create render pipeline descriptor
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction

        // Configure color attachment for transparency
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            print("❌ Failed to create render pipeline state")
            return nil
        }

        print("✅ Metal animator initialized with render pipeline")
        self.renderPipelineState = pipelineState
    }

    func animate(
        window: NSWindow,
        from startFrame: NSRect,
        to endFrame: NSRect,
        duration: TimeInterval,
        onUpdate: @escaping (CGFloat) -> Void,
        completion: @escaping () -> Void
    ) {
        print("🎬 MorphAnimator.animate() called for window: \(window)")

        self.startFrame = startFrame
        self.endFrame = endFrame
        self.duration = duration
        self.animatingWindow = window
        self.onUpdate = onUpdate
        self.onComplete = completion

        // Set up Metal layer for hardware-accelerated rendering
        setupMetalLayer(for: window)

        startTime = CACurrentMediaTime()
        startDisplayLink()
    }

    private func setupMetalLayer(for window: NSWindow) {
        guard let contentView = window.contentView else { return }

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false  // Allow compute shader access
        layer.frame = contentView.bounds
        layer.contentsScale = window.backingScaleFactor
        layer.isOpaque = false  // Allow transparency
        layer.backgroundColor = NSColor.clear.cgColor

        // Replace the view's existing layer with Metal layer
        contentView.wantsLayer = true
        contentView.layer = layer

        // Initialize cached drawable size
        self.cachedDrawableSize = CGSize(
            width: layer.bounds.width * layer.contentsScale,
            height: layer.bounds.height * layer.contentsScale
        )

        self.metalLayer = layer
    }

    private func startDisplayLink() {
        var displayLink: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)

        guard let link = displayLink else {
            print("❌ Failed to create display link")
            return
        }

        print("🎬 Starting display link for animation...")

        CVDisplayLinkSetOutputCallback(link, { (_, _, _, _, _, userInfo) -> CVReturn in
            guard let animator = unsafeBitCast(userInfo, to: MorphAnimator?.self) else {
                print("❌ Display link callback: failed to get animator")
                return kCVReturnError
            }
            animator.update()
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())

        let result = CVDisplayLinkStart(link)
        if result == kCVReturnSuccess {
            print("✅ Display link started successfully")
        } else {
            print("❌ Failed to start display link: \(result)")
        }

        self.displayLink = link
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            print("🛑 Stopping display link")
            CVDisplayLinkStop(link)
            self.displayLink = nil
        }
    }

    deinit {
        print("💀 MorphAnimator deallocated")
        stopDisplayLink()
    }

    private func update() {
        // Perform all calculations on DisplayLink thread (off main thread)
        let elapsed = CACurrentMediaTime() - startTime
        let progress = min(CGFloat(elapsed / duration), 1.0)
        let smoothProgress = easeInOutCubic(progress)

        // Calculate current frame on DisplayLink thread
        let currentFrame = interpolateFrame(progress: smoothProgress)

        // Render with Metal on DisplayLink thread (Metal is thread-safe)
        renderWithMetal(progress: Float(smoothProgress), frameSize: currentFrame.size)

        // Only dispatch to main for window updates and callbacks
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Use CATransaction to batch updates and disable implicit animations
            CATransaction.begin()
            CATransaction.setDisableActions(true)

            // Update window frame (must be on main thread)
            self.animatingWindow?.setFrame(currentFrame, display: false)

            CATransaction.commit()

            // Trigger update callback
            self.onUpdate?(smoothProgress)

            // Check for completion
            if progress >= 1.0 {
                self.stopDisplayLink()
                self.onComplete?()
            }
        }
    }

    private func renderWithMetal(progress: Float, frameSize: NSSize) {
        guard let metalLayer = metalLayer else { return }
        guard let drawable = metalLayer.nextDrawable() else { return }

        // Calculate target drawable size
        let targetSize = CGSize(
            width: frameSize.width * metalLayer.contentsScale,
            height: frameSize.height * metalLayer.contentsScale
        )

        // Only update if size actually changed (cached comparison)
        if cachedDrawableSize != targetSize {
            metalLayer.drawableSize = targetSize
            cachedDrawableSize = targetSize
        }

        // Set up render pass descriptor
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        // Create command buffer and render encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        // Set up uniforms
        var uniforms = Uniforms(
            progress: progress,
            startSize: SIMD2<Float>(Float(startFrame.width), Float(startFrame.height)),
            endSize: SIMD2<Float>(Float(endFrame.width), Float(endFrame.height)),
            startPosition: SIMD2<Float>(Float(startFrame.origin.x), Float(startFrame.origin.y)),
            endPosition: SIMD2<Float>(Float(endFrame.origin.x), Float(endFrame.origin.y))
        )

        // Set render pipeline and uniforms
        renderEncoder.setRenderPipelineState(renderPipelineState)
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)

        // Draw fullscreen quad as triangle strip (4 vertices)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func interpolateFrame(progress: CGFloat) -> NSRect {
        let x = startFrame.origin.x + (endFrame.origin.x - startFrame.origin.x) * progress
        let y = startFrame.origin.y + (endFrame.origin.y - startFrame.origin.y) * progress
        let width = startFrame.size.width + (endFrame.size.width - startFrame.size.width) * progress
        let height = startFrame.size.height + (endFrame.size.height - startFrame.size.height) * progress

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func easeInOutCubic(_ t: CGFloat) -> CGFloat {
        if t < 0.5 {
            return 4.0 * t * t * t
        } else {
            let f = (2.0 * t) - 2.0
            return 0.5 * f * f * f + 1.0
        }
    }
}
