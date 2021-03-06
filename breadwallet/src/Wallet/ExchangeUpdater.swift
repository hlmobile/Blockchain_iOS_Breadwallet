//
//  ExchangeUpdater.swift
//  breadwallet
//
//  Created by Adrian Corscadden on 2017-01-27.
//  Copyright © 2017 breadwallet LLC. All rights reserved.
//

import Foundation

class ExchangeUpdater : Subscriber {

    let currencies: [CurrencyDef]
    
    //MARK: - Public
    init(currencies: [CurrencyDef]) {
        self.currencies = currencies
        currencies.forEach { currency in
            Store.subscribe(self,
                            selector: { $0.defaultCurrencyCode != $1.defaultCurrencyCode },
                            callback: { state in
                                guard let currentRate = state[currency]!.rates.first( where: { $0.code == state.defaultCurrencyCode }) else { return }
                                Store.perform(action: WalletChange(currency).setExchangeRate(currentRate))
            })
        }
    }

    func refresh(completion: @escaping () -> Void) {
        // get btc/fiat rates
        Backend.apiClient.exchangeRates(currencyCode: Currencies.btc.code) { [weak self] result in
            guard let `self` = self,
                case .success(let btcFiatRates) = result else { return }
            
            Store.perform(action: WalletChange(Currencies.btc).setExchangeRates(currentRate: self.findCurrentRate(rates: btcFiatRates), rates: btcFiatRates))
            
            // get token/btc rates
            Backend.apiClient.tokenExchangeRates() { [weak self] result in
                guard let `self` = self,
                    case .success(let tokenBtcRates) = result else { return }
                
                // calculate token/fiat rates
                var tokenBtcDict = [String: Double]()
                tokenBtcRates.forEach { tokenBtcDict[$0.reciprocalCode] = $0.rate }
                Store.state.currencies.filter({ !$0.matches(Currencies.btc) }).forEach { currency in
                    guard let tokenBtcRate = tokenBtcDict[currency.code.lowercased()] else { return }
                    let fiatRates: [Rate] = btcFiatRates.map { btcFiatRate in
                        let tokenFiatRate = btcFiatRate.rate * tokenBtcRate
                        return Rate(code: btcFiatRate.code, name: btcFiatRate.name, rate: tokenFiatRate, reciprocalCode: currency.code.lowercased())
                    }
                    Store.perform(action: WalletChange(currency).setExchangeRates(currentRate: self.findCurrentRate(rates: fiatRates), rates: fiatRates))
                }
                
                // TODO: HACK for CCC (based on price in ETH)
                let tokenCode = StoredTokenData.ccc.code
                guard let token = Store.state.currencies.filter({ $0.code.caseInsensitiveCompare(tokenCode) == .orderedSame }).first else { return }
                Backend.apiClient.exchangeRates(currencyCode: tokenCode) { [weak self] result in
                    guard let `self` = self,
                        case .success(let tokenEthRates) = result,
                        let tokenEthRate = tokenEthRates.first, tokenEthRate.code.caseInsensitiveCompare(Currencies.eth.code) == .orderedSame,
                        let ethFiatRates = Store.state[Currencies.eth]?.rates else { return }
                    
                    let tokenFiatRates: [Rate] = ethFiatRates.map { ethFiatRate in
                        let tokenFiatRate = ethFiatRate.rate * tokenEthRate.rate
                        return Rate(code: ethFiatRate.code, name: ethFiatRate.name, rate: tokenFiatRate, reciprocalCode: tokenCode.lowercased())
                    }
                    Store.perform(action: WalletChange(token).setExchangeRates(currentRate: self.findCurrentRate(rates: tokenFiatRates), rates: tokenFiatRates))
                }
            }
        }
    }

    private func findCurrentRate(rates: [Rate]) -> Rate {
        guard let currentRate = rates.first( where: { $0.code == Store.state.defaultCurrencyCode }) else {
            Store.perform(action: DefaultCurrency.setDefault(C.usdCurrencyCode))
            return rates.first( where: { $0.code == C.usdCurrencyCode })!
        }
        return currentRate
    }
}
