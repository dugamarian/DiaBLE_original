import SwiftUI
import Charts


extension MeasurementColor {
    var color: Color {
        switch self {
        case .green:  .green
        case .yellow: .yellow
        case .orange: .orange
        case .red:    .red
        }
    }
}


struct OnlineView: View, LoggingView {
    @Environment(AppState.self) var app: AppState
    @Environment(History.self) var history: History
    @Environment(Settings.self) var settings: Settings

    @Environment(\.colorScheme) var colorScheme

    @State private var showingNFCAlert = false
    @State private var onlineCountdown: Int = 0
    @State private var readingCountdown: Int = 0

    @State private var libreLinkUpResponse: String = "[...]"

    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()


    var body: some View {
        NavigationView {

            // Workaround to avoid top textfields scrolling offscreen in iOS 14
            GeometryReader { _ in
                VStack(spacing: 0) {

                    HStack(alignment: .top, spacing: 2) {

                        Button {
                            settings.selectedService = settings.selectedService == .nightscout ? .libreLinkUp : .nightscout
                        } label: {
                            Image(settings.selectedService.rawValue).resizable().frame(width: 32, height: 32).shadow(color: .cyan, radius: 4.0 )
                        }
                        .padding(.top, 8).padding(.trailing, 4)

                        VStack(spacing: 0) {

                            @Bindable var settings = settings

                            if settings.selectedService == .nightscout {
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    Text("https://")
                                        .foregroundStyle(Color(.lightGray))
                                    TextField("Nightscout URL", text: $settings.nightscoutSite)
                                        .keyboardType(.URL)
                                        .textContentType(.URL)
                                        .autocorrectionDisabled(true)
                                }
                                SecureField("token", text: $settings.nightscoutToken)
                                    .textContentType(.password)


                            } else if settings.selectedService == .libreLinkUp {
                                TextField("email", text: $settings.libreLinkUpEmail)
                                    .keyboardType(.emailAddress)
                                    .textContentType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .onSubmit {
                                        settings.libreLinkUpUserId = ""
                                        libreLinkUpResponse = "[Logging in...]"
                                        Task {
                                            libreLinkUpResponse = await app.main.libreLinkUp?.reload() ?? "[...]"
                                        }
                                    }
                                SecureField("password", text: $settings.libreLinkUpPassword)
                                    .textContentType(.password)
                                    .onSubmit {
                                        settings.libreLinkUpUserId = ""
                                        libreLinkUpResponse = "[Logging in...]"
                                        Task {
                                            libreLinkUpResponse = await app.main.libreLinkUp?.reload() ?? "[...]"
                                        }
                                    }
                            }
                        }

                        Spacer()

                        Button {
                            withAnimation { settings.libreLinkUpFollowing.toggle() }
                            libreLinkUpResponse = "[Logging in...]"
                            settings.libreLinkUpUserId = ""
                            Task {
                                libreLinkUpResponse = await app.main.libreLinkUp?.reload() ?? "[...]"
                            }
                        } label: {
                            Image(systemName: settings.libreLinkUpFollowing ? "f.circle.fill" : "f.circle").font(.title)
                        }

                        VStack(spacing: 0) {

                            Button {
                                withAnimation { settings.libreLinkUpScrapingLogbook.toggle() }
                                if settings.libreLinkUpScrapingLogbook {
                                    libreLinkUpResponse = "[...]"
                                    Task {
                                        libreLinkUpResponse = await app.main.libreLinkUp?.reload() ?? "[...]"
                                    }
                                }
                            } label: {
                                Image(systemName: settings.libreLinkUpScrapingLogbook ? "book.closed.circle.fill" : "book.closed.circle").font(.title)
                            }

                            Text(onlineCountdown > -1 ? "\(onlineCountdown) s" : "...")
                                .fixedSize()
                                .foregroundStyle(.cyan)
                                .font(.caption.monospacedDigit())
                                .onReceive(timer) { _ in
                                    onlineCountdown = settings.onlineInterval * 60 - Int(Date().timeIntervalSince(settings.lastOnlineDate))
                                }
                        }

                        VStack(spacing: 0) {

                            // TODO: reload web page

                            Button {
                                app.main.rescan()
                                Task {
                                    libreLinkUpResponse = await app.main.libreLinkUp?.reload() ?? "[...]"
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise.circle").font(.title)
                            }

                            Text(!app.deviceState.isEmpty && app.deviceState != "Disconnected" && (readingCountdown > 0 || app.deviceState == "Reconnecting...") ?
                                 "\(readingCountdown) s" : "...")
                            .fixedSize()
                            .foregroundStyle(.orange)
                            .font(.caption.monospacedDigit())
                            .onReceive(timer) { _ in
                                readingCountdown = settings.readingInterval * 60 - Int(Date().timeIntervalSince(app.lastConnectionDate))
                            }
                        }

                        Button {
                            if app.main.nfc.isAvailable {
                                app.main.nfc.startSession()
                                Task {
                                    app.main.healthKit?.read()
                                    if let (values, _) = try? await app.main.nightscout?.read() {
                                        history.nightscoutValues = values
                                    }
                                }
                            } else {
                                showingNFCAlert = true
                            }
                        } label: {
                            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                                .font(.title)
                                .symbolEffect(.variableColor.reversing, isActive: app.deviceState == "Connected")
                        }
                        .alert("NFC not supported", isPresented: $showingNFCAlert) {
                        } message: {
                            Text("This device doesn't allow scanning the Libre.")
                        }
                        .padding(.top, 2)

                    }
                    .foregroundStyle(.tint)
                    .padding(.bottom, 4)
                    #if targetEnvironment(macCatalyst)
                    .padding(.horizontal, 15)
                    #endif

                    if settings.selectedService == .nightscout {

                        @Bindable var app = app

                        WebView(site: settings.nightscoutSite, query: "token=\(settings.nightscoutToken)", delegate: app.main.nightscout )
                            .frame(height: UIScreen.main.bounds.size.height * 0.60)
                            .alert("JavaScript", isPresented: $app.showingJSConfirmAlert) {
                                Button("OK") { log("JavaScript alert: selected OK") }
                                Button("Cancel", role: .cancel) { log("JavaScript alert: selected Cancel") }
                            } message: {
                                Text(app.jsConfirmAlertMessage)
                            }

                        List {
                            ForEach(history.nightscoutValues) { glucose in
                                (Text("\(String(glucose.source[..<(glucose.source.lastIndex(of: " ") ?? glucose.source.endIndex)])) \(glucose.date.shortDateTime)") + Text("  \(glucose.value, specifier: "%3d")").bold())
                                    .fixedSize(horizontal: false, vertical: true).listRowInsets(EdgeInsets())
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .listStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.cyan)
                        #if targetEnvironment(macCatalyst)
                        .padding(.leading, 15)
                        #endif
                        .task {
                            if let (values, _) = try? await app.main.nightscout?.read() {
                                history.nightscoutValues = values
                                log("Nightscout: values read count \(history.nightscoutValues.count)")
                            }
                        }
                    }


                    if settings.selectedService == .libreLinkUp {
                        VStack {
                            ScrollView(showsIndicators: true) {
                                Text(libreLinkUpResponse)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(colorScheme == .dark ? Color(.lightGray) : Color(.darkGray))
                                    .textSelection(.enabled)
                            }
                            #if targetEnvironment(macCatalyst)
                            .padding()
                            #endif

                            if app.main.libreLinkUp?.history.count ?? 0 > 0 {
                                Chart(app.main.libreLinkUp!.history) {
                                    PointMark(x: .value("Time", $0.glucose.date),
                                              y: .value("Glucose", $0.glucose.value)
                                    )
                                    .foregroundStyle($0.color.color)
                                    .symbolSize(12)
                                }
                                .chartXAxis {
                                    AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                                        AxisGridLine()
                                        AxisTick()
                                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute(), anchor: .top)
                                    }
                                }
                                .padding()
                            }

                            HStack {

                                List {
                                    ForEach(app.main.libreLinkUp?.history ?? [LibreLinkUpGlucose]()) { libreLinkUpGlucose in
                                        let glucose = libreLinkUpGlucose.glucose
                                        (Text("\(String(glucose.source[..<(glucose.source.lastIndex(of: " ") ?? glucose.source.endIndex)])) \(glucose.date.shortDateTime)") + Text("  \(glucose.value, specifier: "%3d") ").bold() + Text(libreLinkUpGlucose.trendArrow?.symbol ?? "").font(.subheadline))
                                            .foregroundStyle(libreLinkUpGlucose.color.color)
                                            .fixedSize(horizontal: false, vertical: true).listRowInsets(EdgeInsets())
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                                // TODO: respect onlineInterval
                                .onReceive(minuteTimer) { _ in
                                    Task {
                                        debugLog("DEBUG: fired onlineView minuteTimer: timeInterval: \(Int(Date().timeIntervalSince(settings.lastOnlineDate)))")
                                        if settings.onlineInterval > 0 && Int(Date().timeIntervalSince(settings.lastOnlineDate)) >= settings.onlineInterval * 60 - 5 {
                                            libreLinkUpResponse = await app.main.libreLinkUp?.reload() ?? "[...]"
                                        }
                                    }
                                }

                                if settings.libreLinkUpScrapingLogbook {
                                    // TODO: alarms
                                    List {
                                        ForEach(app.main.libreLinkUp?.logbookHistory ?? [LibreLinkUpGlucose]()) { libreLinkUpGlucose in
                                            let glucose = libreLinkUpGlucose.glucose
                                            (Text("\(String(glucose.source[..<(glucose.source.lastIndex(of: " ") ?? glucose.source.endIndex)])) \(glucose.date.shortDateTime)") + Text("  \(glucose.value, specifier: "%3d") ").bold() + Text(libreLinkUpGlucose.trendArrow!.symbol).font(.subheadline))
                                                .foregroundStyle(libreLinkUpGlucose.color.color)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .listRowInsets(EdgeInsets())
                                        }
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                    }
                                }
                            }
                            .listStyle(.plain)
                            .font(.system(.caption, design: .monospaced))
                        }
                        .task {
                            libreLinkUpResponse = await app.main.libreLinkUp?.reload() ?? "[...]"
                        }
                        #if targetEnvironment(macCatalyst)
                        .padding(.leading, 15)
                        #endif

                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Online")
        }
        .navigationViewStyle(.stack)
    }
}


#Preview {
    ContentView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .online))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}
