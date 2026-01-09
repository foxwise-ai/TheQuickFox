//
//  SiriWaveView.swift
//  TheQuickFox
//
//  A vibrant, multi-color "Siri-style" waveform loader for macOS.
//  Uses a CAReplicatorLayer to create a row of vertical bars whose
//  heights animate with phase offsets, producing a flowing wave.
//
//  Call `start()` / `stop()` to control the animation.
//
//  Created by the TheQuickFox team.
//

import Cocoa
import Combine
import QuartzCore

public final class SiriWaveView: NSView {

    // MARK: – Configuration

    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 2
    private let barCornerRadius: CGFloat = 1.5
    private let animationDuration: CFTimeInterval = 1.2
    private let instanceCount = 32  // number of bars

    private var replicator: CAReplicatorLayer?
    private let theme = ThemeManager.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: – Life-cycle

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        setupThemeBinding()

        // Wave will be built after first layout pass
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.masksToBounds = false
        setupThemeBinding()

        // Wave will be built after first layout pass
    }

    private func setupThemeBinding() {
        theme.$isDarkMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recreateWaveWithNewTheme()
            }
            .store(in: &cancellables)
    }

    private func recreateWaveWithNewTheme() {
        // Recreate wave with new theme colors if it exists
        if replicator != nil && bounds.width > 0 && bounds.height > 0 {
            let wasRunning = replicator?.speed == 1
            createWave()
            if wasRunning {
                start()
            }
        }
    }

    public override func layout() {
        super.layout()
        // Build the wave once we have a valid frame size.
        if replicator == nil && bounds.width > 0 && bounds.height > 0 {
            createWave()
        }
        replicator?.frame = bounds
    }

    // MARK: – Public API

    /// Begin (or resume) animating the waveform.
    public func start() {
        // Build the wave if it hasn’t been created yet.
        if replicator == nil && bounds.width > 0 && bounds.height > 0 {
            createWave()
        }
        replicator?.speed = 1
        replicator?.isHidden = false
    }

    /// Pause animation and hide the wave.
    public func stop() {
        replicator?.speed = 0
        replicator?.isHidden = true
    }

    // MARK: – Internals

    private func createWave() {
        // Clean slate if recreated
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }

        // Replicator layer
        let rep = CAReplicatorLayer()
        rep.frame = bounds
        let barCount = max(4, Int(bounds.width / (barWidth + barSpacing)))
        rep.instanceCount = barCount
        rep.preservesDepth = false
        rep.masksToBounds = false

        // Distribute instances horizontally
        let totalWidth = CGFloat(barCount) * (barWidth + barSpacing) - barSpacing
        let startX = (bounds.width - totalWidth) / 2
        rep.instanceTransform = CATransform3DMakeTranslation(barWidth + barSpacing, 0, 0)
        rep.instanceDelay = animationDuration / CFTimeInterval(barCount)

        // Start paused; will resume when `start()` is called
        rep.speed = 0

        // Prototype bar layer
        let bar = CALayer()
        bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: bounds.height * 0.8)  // taller bars for better visibility
        bar.anchorPoint = CGPoint(x: 0.5, y: 0)  // grow from bottom
        bar.position = CGPoint(x: startX, y: 0)
        bar.cornerRadius = barCornerRadius
        bar.backgroundColor = theme.loaderColor.cgColor

        // Animation – height pulsating with ease-in-out curve
        let anim = CABasicAnimation(keyPath: "bounds.size.height")
        anim.fromValue = bar.bounds.height * 0.4
        anim.toValue = bar.bounds.height
        anim.autoreverses = true
        anim.duration = animationDuration
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bar.add(anim, forKey: "height")

        rep.addSublayer(bar)

        // Apply subtle rainbow offsets directly so bars themselves are colored
        rep.instanceRedOffset = -0.02
        rep.instanceGreenOffset = 0.01
        rep.instanceBlueOffset = 0.02
        layer?.addSublayer(rep)

        replicator = rep
    }
}
