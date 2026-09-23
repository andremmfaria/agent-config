#!/usr/bin/env python3
"""Read-only forex quotes and bars (IDEALPRO CASH contracts) via ib_async.

ibkr-cli 0.7.2 qualifies every symbol as a stock, so forex pairs never resolve
there. This helper covers only the two read paths the trading bot needs.
"""
import argparse
import json
import sys
import time

from ib_async import IB, Forex

HOST = "127.0.0.1"
PORT = 4002
CLIENT_ID = 1


def connect(timeout: float) -> IB:
    ib = IB()
    ib.connect(HOST, PORT, clientId=CLIENT_ID, timeout=timeout, readonly=True)
    return ib


def pair(symbol: str) -> str:
    return symbol.upper().replace(".", "").replace("/", "")


def cmd_quote(args: argparse.Namespace) -> int:
    ib = connect(args.timeout)
    try:
        contract = Forex(pair(args.symbol))
        ib.qualifyContracts(contract)
        ib.reqMarketDataType(1)
        ticker = ib.reqMktData(contract, "", False, False)
        deadline = time.time() + args.timeout
        while time.time() < deadline and (ticker.bid != ticker.bid or ticker.ask != ticker.ask):
            ib.sleep(0.2)
        ib.cancelMktData(contract)
        out = {
            "symbol": contract.symbol + "." + contract.currency,
            "conId": contract.conId,
            "exchange": contract.exchange,
            "bid": ticker.bid,
            "ask": ticker.ask,
            "last": ticker.last,
            "bidSize": ticker.bidSize,
            "askSize": ticker.askSize,
            "high": ticker.high,
            "low": ticker.low,
            "close": ticker.close,
            "time": ticker.time.isoformat() if ticker.time else None,
        }
        ok = out["bid"] == out["bid"] and out["ask"] == out["ask"]
        if args.json:
            print(json.dumps({"ok": ok, **out}, default=str))
        else:
            for k, v in out.items():
                print(f"{k:9} {v}")
        return 0 if ok else 5
    finally:
        ib.disconnect()


def cmd_bars(args: argparse.Namespace) -> int:
    ib = connect(args.timeout)
    try:
        contract = Forex(pair(args.symbol))
        ib.qualifyContracts(contract)
        bars = ib.reqHistoricalData(
            contract,
            endDateTime="",
            durationStr=args.duration,
            barSizeSetting=args.bar_size,
            whatToShow=args.what_to_show,
            useRTH=False,
            formatDate=2,
        )
        data = [
            {"date": b.date.isoformat(), "open": b.open, "high": b.high, "low": b.low,
             "close": b.close, "volume": b.volume, "barCount": b.barCount}
            for b in bars
        ]
        if args.json:
            print(json.dumps({"ok": bool(data), "symbol": contract.symbol + "." + contract.currency,
                              "count": len(data), "bars": data}, default=str))
        else:
            for r in data:
                print(f"{r['date']}  o={r['open']} h={r['high']} l={r['low']} c={r['close']}")
        return 0 if bars else 5
    finally:
        ib.disconnect()


def main() -> int:
    p = argparse.ArgumentParser(description="Read-only forex quotes and bars via IB Gateway")
    p.add_argument("--timeout", type=float, default=8.0)
    p.add_argument("--json", action="store_true")
    sub = p.add_subparsers(dest="cmd", required=True)
    q = sub.add_parser("quote")
    q.add_argument("symbol", help="pair such as EURUSD or EUR.USD")
    q.set_defaults(fn=cmd_quote)
    b = sub.add_parser("bars")
    b.add_argument("symbol")
    b.add_argument("--duration", default="30 D")
    b.add_argument("--bar-size", default="1 hour")
    b.add_argument("--what-to-show", default="MIDPOINT", help="MIDPOINT, BID, ASK or BID_ASK")
    b.set_defaults(fn=cmd_bars)
    args = p.parse_args()
    try:
        return args.fn(args)
    except Exception as exc:
        msg = {"ok": False, "error": str(exc)}
        print(json.dumps(msg) if args.json else f"error: {exc}", file=sys.stderr if not args.json else sys.stdout)
        return 1


if __name__ == "__main__":
    sys.exit(main())
