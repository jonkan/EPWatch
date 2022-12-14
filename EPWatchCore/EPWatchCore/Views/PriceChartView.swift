//
//  File.swift
//  EPWatchCore
//
//  Created by Jonas Bromö on 2022-09-16.
//

import SwiftUI
import Charts
import WidgetKit

public struct PriceChartView: View {

    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    let currentPrice: PricePoint
    let prices: [PricePoint]
    let limits: PriceLimits
    let currencyPresentation: CurrencyPresentation
    let chartStyle: PriceChartStyle
    let useCurrencyAxisFormat: Bool
    let isChartGestureEnabled: Bool

    @Binding var selectedPrice: PricePoint?
    var displayedPrice: PricePoint {
        return selectedPrice ?? currentPrice
    }

    public init(
        selectedPrice: Binding<PricePoint?>,
        currentPrice: PricePoint,
        prices: [PricePoint],
        limits: PriceLimits,
        currencyPresentation: CurrencyPresentation,
        chartStyle: PriceChartStyle,
        useCurrencyAxisFormat: Bool = false,
        isChartGestureEnabled: Bool = true
    ) {
        _selectedPrice = selectedPrice
        self.currentPrice = currentPrice
        self.prices = prices
        self.limits = limits
        self.currencyPresentation = currencyPresentation
        self.chartStyle = chartStyle
        self.useCurrencyAxisFormat = useCurrencyAxisFormat
        self.isChartGestureEnabled = isChartGestureEnabled
    }

    public var body: some View {
        Group {
            switch chartStyle {
            case .lineInterpolated: lineChart(interpolated: true)
            case .line: lineChart(interpolated: false)
            case .bar: barChart
            }
        }
        .widgetAccentable()
        .chartYAxis {
            if let axisYValues = axisYValues {
                // TODO: Figure out how to present subdivided units (e.g. Cent)
                if useCurrencyAxisFormat && currencyPresentation != .subdivided {
                    AxisMarks(
                        format: currencyAxisFormat,
                        values: axisYValues
                    )
                } else {
                    AxisMarks(values: axisYValues)
                }
            } else {
                if useCurrencyAxisFormat && currencyPresentation != .subdivided {
                    AxisMarks(format: currencyAxisFormat)
                } else {
                    AxisMarks()
                }
            }
        }
        .chartOverlay(content: chartGestureOverlay)
        .padding(.top, widgetRenderingMode != .fullColor ? 5 : 0)
    }

    func lineChart(interpolated: Bool) -> some View {
        Chart {
            ForEach(prices, id: \.date) { p in
                LineMark(
                    x: .value("", p.date),
                    y: .value("", p.price(with: currencyPresentation))
                )
            }
            .interpolationMethod(interpolated ? .monotone : .stepCenter)
            .foregroundStyle(LinearGradient(
                stops: limits.stops(using: prices.priceRange() ?? 0.0...0.0),
                startPoint: .bottom,
                endPoint: .top
            ))

            RuleMark(
                x: .value("", displayedPrice.date)
            )
            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 6]))
            .foregroundStyle(.gray)

            if widgetRenderingMode == .fullColor {
                PointMark(
                    x: .value("", displayedPrice.date),
                    y: .value("", displayedPrice.price(with: currencyPresentation))
                )
                .foregroundStyle(.foreground.opacity(0.6))
                .symbolSize(300)

                PointMark(
                    x: .value("", displayedPrice.date),
                    y: .value("", displayedPrice.price(with: currencyPresentation))
                )
                .foregroundStyle(.background)
                .symbolSize(100)
            }

            PointMark(
                x: .value("", displayedPrice.date),
                y: .value("", displayedPrice.price(with: currencyPresentation))
            )
            .foregroundStyle(limits.color(of: displayedPrice.price))
            .symbolSize(70)
        }
    }

    var barChart: some View {
        GeometryReader { geometry in
            let barWidth = geometry.size.width / (CGFloat(prices.count)*1.5+1)
            return Chart {
                BarMark(
                    x: .value("", displayedPrice.date),
                    width: .fixed(barWidth)
                )
                .foregroundStyle(.gray.opacity(0.3))

                ForEach(prices, id: \.date) { p in
                    BarMark(
                        x: .value("", p.date),
                        y: .value("", p.price(with: currencyPresentation)),
                        width: .fixed(barWidth)
                    )
                    .foregroundStyle(limits.color(of: p.price))
                }
            }
            .chartXScale(range: .plotDimension(startPadding: barWidth/2, endPadding: barWidth/2))
        }
    }

    var axisYValues: [Double]? {
        if currentPrice.dayPriceRange.upperBound <= 1.5 && currencyPresentation != .subdivided {
            return [0.0, 0.5, 1.0, 1.5]
        }
        return nil
    }

    var currencyAxisFormat: FloatingPointFormatStyle<Double>.Currency {
        if currentPrice.dayPriceRange.upperBound <= 10 {
            return .currency(code: currentPrice.currency.code).precision(.fractionLength(1))
        }
        return .currency(code: currentPrice.currency.code).precision(.significantDigits(2))
    }

    func chartGestureOverlay(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Color.clear.contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let origin = geometry[proxy.plotAreaFrame].origin
                            let size = geometry[proxy.plotAreaFrame].size
                            let location = CGPoint(
                                x: max(origin.x, min(value.location.x - origin.x, size.width)),
                                y: max(origin.y, min(value.location.y - origin.y, size.height))
                            )
                            guard let selectedDate = proxy.value(atX: location.x, as: Date.self) else {
                                Log("Failed to find selected X value")
                                return
                            }

                            let secondsToFirst = selectedDate.timeIntervalSince(prices.first?.date ?? .distantPast)
                            let selectedIndex = Int(round(secondsToFirst / 60 / 60))
                            let price = prices[safe: selectedIndex]

                            if selectedPrice != price {
                                selectedPrice = price
                                SelectionHaptics.shared.changed()
                            }
                            cancelSelectionResetTimer()
                        }
                        .onEnded { _ in
                            scheduleSelectionResetTimer(in: .milliseconds(500)) {
                                selectedPrice = nil
                                SelectionHaptics.shared.ended()
                            }
                        },
                    including: isChartGestureEnabled ? .all : .subviews
                )
        }
    }

    @State private var selectionResetTimer : DispatchSourceTimer?
    private func scheduleSelectionResetTimer(
        in timeout: DispatchTimeInterval,
        handler: @escaping () -> Void
    ) {
        if selectionResetTimer == nil {
            let timerSource = DispatchSource.makeTimerSource(queue: .global())
            timerSource.setEventHandler {
                Task {
                    cancelSelectionResetTimer()
                    handler()
                }
            }
            selectionResetTimer = timerSource
            timerSource.resume()
        }
        selectionResetTimer?.schedule(
            deadline: .now() + timeout,
            repeating: .infinity,
            leeway: .milliseconds(50)
        )
    }

    private func cancelSelectionResetTimer() {
        selectionResetTimer?.cancel()
        selectionResetTimer = nil
    }


}

private extension PricePoint {
    func price(with currencyPresentation: CurrencyPresentation) -> Double {
        switch currencyPresentation {
        case .automatic:
            return price
        case .subdivided:
            return price * currency.subdivision.subdivisions
        }
    }
}

struct PriceChartView_Previews: PreviewProvider {
    static var previews: some View {
        List {
            PriceChartView(
                selectedPrice: .constant(nil),
                currentPrice: [PricePoint].mockPricesWithTomorrow[21],
                prices: .mockPricesWithTomorrow,
                limits: .mockLimits,
                currencyPresentation: .automatic,
                chartStyle: .lineInterpolated
            )
            .frame(minHeight: 150)
        }
    }
}
