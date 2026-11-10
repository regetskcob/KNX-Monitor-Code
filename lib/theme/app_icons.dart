import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:horizont/horizont.dart';

/// All icons of the app in one place, named by meaning: Material Symbols Sharp at weight 300 from
/// Horizont (the subset is listed in `icons/material-symbols.txt` in the Horizont repository).
abstract final class AppIcons {
  // Views & navigation
  static const overview = HorizontSymbols.spaceDashboard;
  static const objects = HorizontSymbols.category;
  static const live = HorizontSymbols.bolt;
  static const recordings = HorizontSymbols.videoLibrary;
  static const chart = HorizontSymbols.showChart;
  static const fullscreen = HorizontSymbols.fitScreen;
  static const add = HorizontSymbols.add;
  static const homePlan = HorizontSymbols.map;
  static const list = HorizontSymbols.formatListBulleted;
  static const toTop = HorizontSymbols.arrowUpward;
  static const info = HorizontSymbols.info;
  static const next = HorizontSymbols.chevronRight;
  static const expand = HorizontSymbols.expandMore;
  static const collapse = HorizontSymbols.expandLess;
  static const installation = HorizontSymbols.home;
  static const check = HorizontSymbols.check;
  static const close = HorizontSymbols.close;
  static IconData get more => horizontMoreSymbol(defaultTargetPlatform);
  static const sidebarShow = HorizontSymbols.leftPanelOpen;
  static const sidebarHide = HorizontSymbols.leftPanelClose;

  // Monitor
  static const play = HorizontSymbols.playArrow;
  static const pause = HorizontSymbols.pause;
  static const record = HorizontSymbols.radioButtonChecked;
  static const stop = HorizontSymbols.stop;
  static const trigger = HorizontSymbols.trackChanges;
  static const select = HorizontSymbols.checklist;
  static const clear = HorizontSymbols.deleteSweep;
  static const search = HorizontSymbols.search;
  static const filter = HorizontSymbols.filterList;
  static const sensors = HorizontSymbols.sensors;
  static const secure = HorizontSymbols.lock;
  static const brightness = HorizontSymbols.lightMode;
  static const blinds = HorizontSymbols.blinds;
  static const light = HorizontSymbols.lightbulb;
  static const thermostat = HorizontSymbols.thermostat;
  static const valve = HorizontSymbols.valve;
  static const window = HorizontSymbols.window;
  static const alarm = HorizontSymbols.notificationImportant;
  static const weather = HorizontSymbols.cloud;
  static const energy = HorizontSymbols.electricMeter;
  static const dateTime = HorizontSymbols.schedule;
  static const touch = HorizontSymbols.touchApp;
  static const diagnostics = HorizontSymbols.troubleshoot;
  // To the support team: the same symbol as „Fehler melden“ (report a bug); the octagon stays
  // "critical".
  static const supportPackage = HorizontSymbols.feedback;

  /// Save a file, including the full backup.
  static const save = HorizontSymbols.save;
  static const cloudSync = HorizontSymbols.cloud;
  static const projectCheck = HorizontSymbols.factCheck;
  static const commissioning = HorizontSymbols.assignmentTurnedIn;
  static const notify = HorizontSymbols.notificationsActive;
  static const expert = HorizontSymbols.tune;
  static const health = HorizontSymbols.monitorHeart;
  static const statistics = HorizontSymbols.insights;
  static const communicationMap = HorizontSymbols.hub;
  static const topology = HorizontSymbols.accountTree;
  static const cycle = HorizontSymbols.repeat;
  static const rewind = HorizontSymbols.fastRewind;
  static const forward = HorizontSymbols.fastForward;
  static const undo = HorizontSymbols.undo;
  static const redo = HorizontSymbols.redo;
  static const left = HorizontSymbols.keyboardArrowLeft;
  static const right = HorizontSymbols.keyboardArrowRight;
  static const restart = HorizontSymbols.replay;

  // Actions
  static const write = HorizontSymbols.edit;
  static const send = HorizontSymbols.upload;
  static const read = HorizontSymbols.download;
  static const reply = HorizontSymbols.reply;
  static const copy = HorizontSymbols.contentCopy;
  static IconData get share => horizontShareSymbol(defaultTargetPlatform);
  static const tools = HorizontSymbols.handyman;
  static const pin = HorizontSymbols.pushPinFill;
  static const pinOutline = HorizontSymbols.pushPin;
  static const favorite = HorizontSymbols.starFill;
  static const favoriteOutline = HorizontSymbols.star;
  static const pdf = HorizontSymbols.pictureAsPdf;

  /// Tasks for the ETS (checklist from the project comparison).
  static const etsTasks = HorizontSymbols.checklist;
  static const table = HorizontSymbols.tableChart;
  static const fileCode = HorizontSymbols.dataObject;
  static const edit = HorizontSymbols.editNote;
  static const delete = HorizontSymbols.delete;
  static const import = HorizontSymbols.uploadFile;
  static const disconnect = HorizontSymbols.linkOff;
  static const box = HorizontSymbols.router;
  static const history = HorizontSymbols.history;
  static const language = HorizontSymbols.translate;
  static const bookmark = HorizontSymbols.bookmarks;
  static const bookmarkAdd = HorizontSymbols.bookmarkAdd;
  static const help = HorizontSymbols.help;

  // Comments, screenshots, bug reports
  static const annotation = HorizontSymbols.flag;
  static const annotationSet = HorizontSymbols.flagFill;
  static const image = HorizontSymbols.image;
  static const report = HorizontSymbols.feedback;

  // Status & content
  static const project = HorizontSymbols.label;
  static const noProject = HorizontSymbols.labelOff;
  static const success = HorizontSymbols.checkCircle;
  static const selected = HorizontSymbols.checkCircle;
  static const unselected = HorizontSymbols.radioButtonUnchecked;
  static const sends = HorizontSymbols.northEast;
  static const receives = HorizontSymbols.southWest;
  static const show = HorizontSymbols.visibility;
  static const hide = HorizontSymbols.visibilityOff;

  // Unlocking
  static const plan = HorizontSymbols.star;
  static const locked = HorizontSymbols.lock;
  static const account = HorizontSymbols.person;
  static const watch = HorizontSymbols.notificationsActive;
  static const soundOn = HorizontSymbols.volumeUp;
  static const soundOff = HorizontSymbols.volumeOff;

  /// Sound feedback (tone per telegram).
  static const ack = HorizontSymbols.volumeUp;

  /// Acceptance report and signature.
  static const acceptance = HorizontSymbols.signature;
  static const company = HorizontSymbols.storefront;
  static const serviceReport = HorizontSymbols.build;
  static const customers = HorizontSymbols.groups;
  static const phone = HorizontSymbols.smartphone;
  static const mail = HorizontSymbols.localPostOffice;
  static const place = HorizontSymbols.locationOn;
  static const handover = HorizontSymbols.inventory2;
  static const qrCode = HorizontSymbols.qrCode2;
  static const qrScan = HorizontSymbols.qrCodeScanner;
  static const manual = HorizontSymbols.menuBook;

  /// Fault hunting with the Busclear Box.
  static const hunt = HorizontSymbols.bugReport;

  /// Learning an installation without an ETS project.
  static const teachIn = HorizontSymbols.touchApp;

  /// Learning on your own installation (lessons, quiz).
  static const learn = HorizontSymbols.school;

  /// Glossary.
  static const glossary = HorizontSymbols.menuBook;

  /// Help with the ETS project file.
  static const projectFile = HorizontSymbols.description;

  /// Network (help with connecting).
  static const network = HorizontSymbols.lan;
}
