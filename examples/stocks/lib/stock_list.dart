// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import 'stock_data.dart';
import 'stock_row.dart';

class StockList extends StatelessWidget {
  final List<Stock> stocks;

  final StockRowActionCallback onOpen;
  final StockRowActionCallback onShow;
  final StockRowActionCallback onAction;

  const StockList(
      {Key key, this.stocks, this.onOpen, this.onShow, this.onAction})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return new ListView.builder(
      key: const ValueKey<String>('stock-list'),
      itemExtent: StockRow.kHeight,
      itemCount: stocks.length,
      itemBuilder: (BuildContext context, int index) {
        return new StockRow(
            stock: stocks[index],
            onPressed: onOpen,
            onDoubleTap: onShow,
            onLongPressed: onAction);
      },
    );
  }
}