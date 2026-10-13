import PhotosUI
import SwiftUI
import UIKit

/// Full-screen receipt scanner: camera → on-device Vision text recognition → review → add to pantry.
struct ScanView: View {
    @Environment(PantryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var camera: CameraService = CameraService()
    @State private var capturedImage: UIImage?
    @State private var receipt: ScannedReceipt?
    @State private var errorMessage: String?
    @State private var isProcessing: Bool = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var shutterFlash: Bool = false
    @State private var captureTick: Int = 0
    @State private var pendingReceipt: ScannedReceipt?
    @State private var showNewStoreDialog: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let receipt {
                ReceiptReviewView(
                    receipt: receipt,
                    onRescan: resetToCamera,
                    onConfirm: { confirmed in
                        // Bekannter Laden → direkt zuordnen. Neuer Laden →
                        // erst fragen, ob ein eigener Slider angelegt werden soll.
                        if store.hasStore(confirmed.store) {
                            store.add(receipt: confirmed, assignStore: true)
                            dismiss()
                        } else {
                            pendingReceipt = confirmed
                            showNewStoreDialog = true
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                scannerLayer
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: receipt != nil)
        .confirmationDialog(
            "Möchtest du \(pendingReceipt?.store ?? "den Laden") als eigenen Extra-Slider/Kategorie hinzufügen?",
            isPresented: $showNewStoreDialog,
            titleVisibility: .visible
        ) {
            Button("Als Slider hinzufügen") { confirmPending(asSlider: true) }
            Button("Nur in „Alle Läden“ einsortieren") { confirmPending(asSlider: false) }
            Button("Abbrechen", role: .cancel) { pendingReceipt = nil }
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPicked(item) }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: captureTick)
        .sensoryFeedback(.success, trigger: receipt != nil) { _, new in new }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
    }

    // MARK: Scanner

    private var scannerLayer: some View {
        ZStack {
            cameraLayer.ignoresSafeArea()

            LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            Color.white.opacity(shutterFlash ? 0.8 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack {
                    GlassCircleButton(systemImage: "xmark", size: 48, iconSize: 18, label: "Schließen") { dismiss() }
                    Spacer()
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .glassSurface(Circle(), interactive: true)
                    }
                    .accessibilityLabel("Foto aus Mediathek wählen")
                    .disabled(isProcessing)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                ScanFrame(isScanning: isProcessing)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 20)
                    .frame(maxHeight: .infinity)

                hintBanner
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                controls
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private var cameraLayer: some View {
        if let capturedImage {
            Color.black.overlay {
                Image(uiImage: capturedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .allowsHitTesting(false)
            }
            .clipped()
        } else {
            switch camera.state {
            case .running:
                CameraPreview(session: camera.session)
            case .denied:
                cameraMessage(
                    icon: "camera.fill",
                    title: "Kein Kamerazugriff",
                    text: "Erlaube den Kamerazugriff in den Einstellungen, um Kassenbons zu scannen – oder wähle ein Foto aus deiner Mediathek.",
                    showSettings: true
                )
            case .unavailable, .failed:
                cameraMessage(
                    icon: "camera.metering.unknown",
                    title: "Keine Kamera gefunden",
                    text: "Wähle oben rechts ein Foto deines Kassenbons aus der Mediathek.",
                    showSettings: false
                )
            case .idle, .requesting:
                Color.black
            }
        }
    }

    private func cameraMessage(icon: String, title: String, text: String, showSettings: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Theme.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            if showSettings {
                Button("Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.white, in: .capsule)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var hintBanner: some View {
        HStack(spacing: 12) {
            Group {
                if isProcessing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: errorMessage == nil ? "doc.text" : "exclamationmark.triangle")
                        .font(.system(size: 17, weight: .medium))
                }
            }
            .frame(width: 34, height: 34)
            .background(Color.white.opacity(0.12), in: .circle)

            Text(bannerText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassSurface(RoundedRectangle(cornerRadius: 24))
        .animation(.easeInOut(duration: 0.25), value: bannerText)
    }

    private var bannerText: String {
        if isProcessing { return "Kassenbon wird lokal gelesen …" }
        if let errorMessage { return errorMessage }
        return "Kassenbon im Rahmen positionieren"
    }

    private var controls: some View {
        HStack {
            Button {
                camera.toggleTorch()
            } label: {
                Image(systemName: camera.isTorchOn ? "bolt.fill" : "bolt")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .glassSurface(Circle(), interactive: true)
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .opacity(camera.hasTorch ? 1 : 0.4)
            .disabled(!camera.hasTorch || isProcessing)
            .accessibilityLabel("Blitz")

            Spacer()

            Button(action: shoot) {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 82, height: 82)
                    Circle().fill(.white).frame(width: 68, height: 68)
                        .scaleEffect(isProcessing ? 0.6 : 1)
                        .opacity(isProcessing ? 0.5 : 1)
                }
                .contentShape(.circle)
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .disabled(isProcessing || camera.state != .running || capturedImage != nil)
            .opacity(camera.state == .running || isProcessing ? 1 : 0.35)
            .accessibilityLabel("Kassenbon fotografieren")

            Spacer()

            Button {
                if capturedImage != nil && !isProcessing {
                    resetToCamera()
                } else {
                    dismiss()
                }
            } label: {
                Text(capturedImage != nil && !isProcessing ? "Neu" : "Abbrechen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                    .glassSurface(Capsule(), interactive: true)
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: Actions

    private func shoot() {
        captureTick += 1
        withAnimation(.easeOut(duration: 0.08)) { shutterFlash = true }
        withAnimation(.easeIn(duration: 0.35).delay(0.08)) { shutterFlash = false }
        Task {
            guard let image = await camera.capture() else {
                errorMessage = "Foto konnte nicht aufgenommen werden. Bitte versuche es erneut."
                return
            }
            await process(image)
        }
    }

    private func loadPicked(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            errorMessage = "Das Foto konnte nicht geladen werden."
            return
        }
        await process(image)
    }

    private func process(_ image: UIImage) async {
        capturedImage = image
        errorMessage = nil
        isProcessing = true
        camera.stop()
        do {
            let result = try await VisionReceiptService.parseReceipt(image: image)
            isProcessing = false
            receipt = result
        } catch {
            isProcessing = false
            errorMessage = (error as? LocalizedError)?.errorDescription ?? AIError.server.errorDescription
        }
    }

    private func resetToCamera() {
        receipt = nil
        capturedImage = nil
        errorMessage = nil
        isProcessing = false
        Task { await camera.start() }
    }

    /// Fügt den gescannten Bon hinzu – optional mit neuem Marken-Slider.
    private func confirmPending(asSlider: Bool) {
        guard let confirmed = pendingReceipt else { return }
        if asSlider {
            _ = store.addStore(name: confirmed.store, colorHex: confirmed.storeColorHex)
        }
        store.add(receipt: confirmed, assignStore: asSlider)
        pendingReceipt = nil
        dismiss()
    }
}

/// Four corner brackets with an optional sweeping scan line.
struct ScanFrame: View {
    let isScanning: Bool
    @State private var sweep: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CornerBrackets()
                    .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                if isScanning {
                    LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 70)
                        .offset(y: sweep ? geo.size.height / 2 - 35 : -geo.size.height / 2 + 35)
                        .blendMode(.plusLighter)
                        .onAppear {
                            sweep = false
                            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { sweep = true }
                        }
                }
            }
        }
        .aspectRatio(0.62, contentMode: .fit)
        .allowsHitTesting(false)
    }
}

struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let len = min(rect.width, rect.height) * 0.14
        let r: CGFloat = 16
        var p = Path()
        // top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + len))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))
        // top-right
        p.move(to: CGPoint(x: rect.maxX - len, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + len))
        // bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - len))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - len, y: rect.maxY))
        // bottom-left
        p.move(to: CGPoint(x: rect.minX + len, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - len))
        return p
    }
}
