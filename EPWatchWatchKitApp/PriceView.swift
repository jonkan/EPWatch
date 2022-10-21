//
//  PriceView.swift
//  EPWatchWatchKitApp
//
//  Created by Jonas Bromö on 2022-09-13.
//

import SwiftUI
import Charts
import EPWatchCore

struct PriceView: View {

    var currentPrice: PricePoint
    var prices: [PricePoint]

    var body: some View {
        VStack(spacing: 8) {
            Text(currentPrice.formattedPrice(.normal))
                .font(.title)
            Text(currentPrice.formattedTimeInterval(.normal))
                .font(.subheadline)
            Chart {
                ForEach(prices, id: \.date) { p in
                    LineMark(
                        x: .value("", p.date),
                        y: .value("Kr", p.price)
                    )
                }
                RuleMark(
                    x: .value("", currentPrice.date)
                )
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [2, 4]))
                .foregroundStyle(.gray)
                PointMark(
                    x: .value("", currentPrice.date),
                    y: .value("Kr", currentPrice.price)
                )
            }
        }
    }

}

struct PriceView_Previews: PreviewProvider {
    static var previews: some View {
        PriceView(
            currentPrice: .mockPrices[10],
            prices: PricePoint.mockPrices
        )
    }
}
