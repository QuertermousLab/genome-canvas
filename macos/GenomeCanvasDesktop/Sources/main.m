#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#include <math.h>
#include <stdio.h>

static NSString * const GCDefaultServerAddress = @"http://171.65.68.140:8892/genome-canvas/";
static NSString * const GCServerDefaultsKey = @"GenomeCanvasServerAddress";
static NSPasteboardType const GCTrackRowPasteboardType = @"org.genomecanvas.desktop.track-row";

@interface GCAppDelegate : NSObject <NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler, NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) NSSegmentedControl *connectionModeControl;
@property(nonatomic, strong) NSTextField *workspaceLabel;
@property(nonatomic, strong) NSStackView *workspaceControls;
@property(nonatomic, strong) NSPopUpButton *workspacePopup;
@property(nonatomic, strong) NSButton *deleteWorkspaceButton;
@property(nonatomic, strong) NSButton *filesButton;
@property(nonatomic, strong) NSMenuItem *openFilesMenuItem;
@property(nonatomic, strong) NSMenuItem *localBackendMenuItem;
@property(nonatomic, strong) NSMenuItem *remoteServerMenuItem;
@property(nonatomic, strong) NSLayoutConstraint *remoteSourceTopConstraint;
@property(nonatomic, strong) NSLayoutConstraint *localSourceTopConstraint;
@property(nonatomic, strong) NSPopUpButton *genomePopup;
@property(nonatomic, strong) NSTextField *locusField;
@property(nonatomic, strong) NSTextField *statusDot;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSTextField *trackCountLabel;
@property(nonatomic, strong) NSTableView *trackTable;
@property(nonatomic, strong) NSButton *removeTrackButton;
@property(nonatomic, strong) NSButton *highlightButton;
@property(nonatomic, strong) NSButton *clearHighlightsButton;
@property(nonatomic, strong) NSColorWell *highlightColorWell;
@property(nonatomic, strong) NSButton *reloadButton;
@property(nonatomic, strong) NSProgressIndicator *progressIndicator;
@property(nonatomic, strong) NSMapTable<WKDownload *, NSURL *> *downloadDestinations;
@property(nonatomic, copy) NSArray<NSDictionary *> *tracks;
@property(nonatomic, copy) NSArray<NSDictionary *> *workspaces;
@property(nonatomic, copy) NSString *serverAddress;
@property(nonatomic) BOOL localMode;
@property(nonatomic, strong) NSTask *localServerTask;
@property(nonatomic, strong) NSFileHandle *localServerLogHandle;
@property(nonatomic, copy) NSString *localServerAddress;
@end

@implementation GCAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.downloadDestinations = [NSMapTable weakToStrongObjectsMapTable];
    self.tracks = @[];
    self.workspaces = @[];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *savedAddress = [defaults stringForKey:GCServerDefaultsKey];
    self.serverAddress = savedAddress ?: GCDefaultServerAddress;
    self.localMode = NO;
    [self buildApplicationMenu];

    NSRect frame = NSMakeRect(0, 0, 1480, 900);
    NSWindowStyleMask style = NSWindowStyleMaskTitled
        | NSWindowStyleMaskClosable
        | NSWindowStyleMaskMiniaturizable
        | NSWindowStyleMaskResizable;
    self.window = [[NSWindow alloc] initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Genome Canvas";
    self.window.subtitle = @"Native genomics workbench";
    self.window.minSize = NSMakeSize(1120, 680);
    self.window.titlebarAppearsTransparent = NO;
    self.window.backgroundColor = [NSColor windowBackgroundColor];
    [self.window center];

    NSSplitView *splitView = [[NSSplitView alloc] initWithFrame:frame];
    splitView.translatesAutoresizingMaskIntoConstraints = NO;
    splitView.vertical = YES;
    splitView.dividerStyle = NSSplitViewDividerStyleThin;
    self.window.contentView = splitView;

    NSVisualEffectView *sidebar = [self buildSidebar];
    NSView *content = [self buildGenomeContent];
    [splitView addArrangedSubview:sidebar];
    [splitView addArrangedSubview:content];
    [sidebar.widthAnchor constraintEqualToConstant:264].active = YES;

    [self.webView addObserver:self forKeyPath:@"estimatedProgress"
                      options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:NULL];

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self updateConnectionUI];
    if (self.localMode) [self startLocalBackend];
    else [self loadServerAddress:self.serverAddress remember:NO];
}

- (NSVisualEffectView *)buildSidebar {
    NSVisualEffectView *sidebar = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    sidebar.material = NSVisualEffectMaterialSidebar;
    sidebar.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    sidebar.state = NSVisualEffectStateActive;

    NSTextField *mark = [NSTextField labelWithString:@"G"];
    mark.alignment = NSTextAlignmentCenter;
    mark.font = [NSFont systemFontOfSize:21 weight:NSFontWeightBold];
    mark.textColor = [NSColor colorWithCalibratedRed:0.36 green:0.40 blue:0.43 alpha:1.0];
    mark.wantsLayer = YES;
    mark.layer.cornerRadius = 8;
    mark.layer.borderWidth = 1;
    mark.layer.borderColor = [NSColor separatorColor].CGColor;
    mark.layer.backgroundColor = [NSColor colorWithCalibratedWhite:1 alpha:0.38].CGColor;

    NSTextField *title = [NSTextField labelWithString:@"Genome Canvas"];
    title.font = [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold];
    NSTextField *subtitle = [NSTextField labelWithString:@"GENOMICS WORKBENCH"];
    subtitle.font = [NSFont systemFontOfSize:9 weight:NSFontWeightSemibold];
    subtitle.textColor = [NSColor tertiaryLabelColor];
    NSStackView *brandCopy = [NSStackView stackViewWithViews:@[title, subtitle]];
    brandCopy.orientation = NSUserInterfaceLayoutOrientationVertical;
    brandCopy.alignment = NSLayoutAttributeLeading;
    brandCopy.spacing = 2;
    NSStackView *brand = [NSStackView stackViewWithViews:@[mark, brandCopy]];
    brand.translatesAutoresizingMaskIntoConstraints = NO;
    brand.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    brand.alignment = NSLayoutAttributeCenterY;
    brand.spacing = 11;
    [sidebar addSubview:brand];

    NSTextField *sourceLabel = [self sectionLabel:@"DATA SOURCE"];
    self.connectionModeControl = [NSSegmentedControl segmentedControlWithLabels:@[@"This Mac", @"Server"]
        trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changeConnectionMode:)];
    self.connectionModeControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.connectionModeControl.selectedSegment = self.localMode ? 0 : 1;
    [sidebar addSubview:sourceLabel];
    [sidebar addSubview:self.connectionModeControl];

    self.workspaceLabel = [self sectionLabel:@"WORKSPACE"];
    self.workspacePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.workspacePopup.translatesAutoresizingMaskIntoConstraints = NO;
    self.workspacePopup.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.workspacePopup.target = self;
    self.workspacePopup.action = @selector(changeWorkspace:);
    [self.workspacePopup addItemWithTitle:@"Choose Workspace…"];
    [self.workspacePopup setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.workspacePopup setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSButton *createWorkspaceButton = [self compactButton:@"plus" tip:@"Create temporary project" action:@selector(createWorkspace:)];
    self.deleteWorkspaceButton = [self compactButton:@"trash" tip:@"Delete selected temporary project" action:@selector(deleteWorkspace:)];
    self.deleteWorkspaceButton.enabled = NO;
    NSButton *manageWorkspaceButton = [self compactButton:@"gearshape" tip:@"Manage all workspaces" action:@selector(manageWorkspaces:)];
    self.workspaceControls = [NSStackView stackViewWithViews:@[
        self.workspacePopup, createWorkspaceButton, self.deleteWorkspaceButton, manageWorkspaceButton
    ]];
    self.workspaceControls.translatesAutoresizingMaskIntoConstraints = NO;
    self.workspaceControls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.workspaceControls.alignment = NSLayoutAttributeCenterY;
    self.workspaceControls.spacing = 5;
    [sidebar addSubview:self.workspaceLabel];
    [sidebar addSubview:self.workspaceControls];

    self.filesButton = [self sidebarButton:@"Open Server Files" symbol:@"externaldrive" action:@selector(openServerFiles:)];
    NSButton *publicButton = [self sidebarButton:@"Public Data" symbol:@"network" action:@selector(openPublicData:)];
    NSButton *referenceButton = [self sidebarButton:@"Custom Reference" symbol:@"circle.grid.cross" action:@selector(openCustomReference:)];
    publicButton.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    referenceButton.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    publicButton.alignment = NSTextAlignmentCenter;
    referenceButton.alignment = NSTextAlignmentCenter;
    NSView *sourceButtons = [[NSView alloc] initWithFrame:NSZeroRect];
    sourceButtons.translatesAutoresizingMaskIntoConstraints = NO;
    [sourceButtons addSubview:self.filesButton];
    [sourceButtons addSubview:publicButton];
    [sourceButtons addSubview:referenceButton];
    [sidebar addSubview:sourceButtons];

    [NSLayoutConstraint activateConstraints:@[
        [self.filesButton.topAnchor constraintEqualToAnchor:sourceButtons.topAnchor],
        [self.filesButton.leadingAnchor constraintEqualToAnchor:sourceButtons.leadingAnchor],
        [self.filesButton.trailingAnchor constraintEqualToAnchor:sourceButtons.trailingAnchor],
        [publicButton.topAnchor constraintEqualToAnchor:self.filesButton.bottomAnchor constant:7],
        [publicButton.leadingAnchor constraintEqualToAnchor:sourceButtons.leadingAnchor],
        [referenceButton.topAnchor constraintEqualToAnchor:publicButton.topAnchor],
        [referenceButton.leadingAnchor constraintEqualToAnchor:publicButton.trailingAnchor constant:7],
        [referenceButton.trailingAnchor constraintEqualToAnchor:sourceButtons.trailingAnchor],
        [referenceButton.widthAnchor constraintEqualToAnchor:publicButton.widthAnchor],
        [referenceButton.bottomAnchor constraintEqualToAnchor:sourceButtons.bottomAnchor]
    ]];

    NSTextField *tracksLabel = [self sectionLabel:@"TRACKS"];
    self.trackCountLabel = [NSTextField labelWithString:@"0"];
    self.trackCountLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium];
    self.trackCountLabel.textColor = [NSColor secondaryLabelColor];
    NSStackView *trackHeading = [NSStackView stackViewWithViews:@[tracksLabel, self.trackCountLabel]];
    trackHeading.translatesAutoresizingMaskIntoConstraints = NO;
    trackHeading.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    trackHeading.distribution = NSStackViewDistributionFill;
    [sidebar addSubview:trackHeading];

    self.trackTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *trackColumn = [[NSTableColumn alloc] initWithIdentifier:@"track"];
    trackColumn.resizingMask = NSTableColumnAutoresizingMask;
    [self.trackTable addTableColumn:trackColumn];
    self.trackTable.headerView = nil;
    self.trackTable.rowHeight = 54;
    self.trackTable.intercellSpacing = NSMakeSize(0, 2);
    self.trackTable.backgroundColor = [NSColor clearColor];
    self.trackTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    self.trackTable.delegate = self;
    self.trackTable.dataSource = self;
    self.trackTable.target = self;
    self.trackTable.action = @selector(trackSelectionChanged:);
    [self.trackTable registerForDraggedTypes:@[GCTrackRowPasteboardType]];
    self.trackTable.draggingDestinationFeedbackStyle = NSTableViewDraggingDestinationFeedbackStyleGap;
    self.trackTable.verticalMotionCanBeginDrag = YES;

    NSScrollView *trackScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    trackScroll.translatesAutoresizingMaskIntoConstraints = NO;
    trackScroll.documentView = self.trackTable;
    trackScroll.hasVerticalScroller = YES;
    trackScroll.autohidesScrollers = YES;
    trackScroll.drawsBackground = NO;
    trackScroll.borderType = NSNoBorder;
    [sidebar addSubview:trackScroll];

    self.removeTrackButton = [self sidebarButton:@"Remove Selected Track" symbol:@"minus.circle" action:@selector(removeSelectedTrack:)];
    self.removeTrackButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.removeTrackButton.enabled = NO;
    [sidebar addSubview:self.removeTrackButton];

    self.statusDot = [NSTextField labelWithString:@"●"];
    self.statusDot.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    self.statusLabel = [NSTextField labelWithString:@"Connecting"];
    self.statusLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    NSStackView *status = [NSStackView stackViewWithViews:@[self.statusDot, self.statusLabel]];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    status.spacing = 6;
    [sidebar addSubview:status];

    [NSLayoutConstraint activateConstraints:@[
        [mark.widthAnchor constraintEqualToConstant:42], [mark.heightAnchor constraintEqualToConstant:42],
        [brand.topAnchor constraintEqualToAnchor:sidebar.safeAreaLayoutGuide.topAnchor constant:18],
        [brand.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:16],
        [brand.trailingAnchor constraintLessThanOrEqualToAnchor:sidebar.trailingAnchor constant:-12],
        [sourceLabel.topAnchor constraintEqualToAnchor:brand.bottomAnchor constant:22],
        [sourceLabel.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:16],
        [self.connectionModeControl.topAnchor constraintEqualToAnchor:sourceLabel.bottomAnchor constant:5],
        [self.connectionModeControl.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:13],
        [self.connectionModeControl.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-13],
        [self.connectionModeControl.heightAnchor constraintEqualToConstant:30],
        [self.workspaceLabel.topAnchor constraintEqualToAnchor:self.connectionModeControl.bottomAnchor constant:14],
        [self.workspaceLabel.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:16],
        [self.workspaceControls.topAnchor constraintEqualToAnchor:self.workspaceLabel.bottomAnchor constant:5],
        [self.workspaceControls.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:13],
        [self.workspaceControls.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-13],
        [self.workspacePopup.heightAnchor constraintEqualToConstant:30],
        [sourceButtons.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:13],
        [sourceButtons.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-13],
        [trackHeading.topAnchor constraintEqualToAnchor:sourceButtons.bottomAnchor constant:22],
        [trackHeading.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:16],
        [trackHeading.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-16],
        [trackScroll.topAnchor constraintEqualToAnchor:trackHeading.bottomAnchor constant:7],
        [trackScroll.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:8],
        [trackScroll.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-8],
        [self.removeTrackButton.topAnchor constraintEqualToAnchor:trackScroll.bottomAnchor constant:7],
        [self.removeTrackButton.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:13],
        [self.removeTrackButton.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-13],
        [status.topAnchor constraintEqualToAnchor:self.removeTrackButton.bottomAnchor constant:12],
        [status.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:16],
        [status.trailingAnchor constraintLessThanOrEqualToAnchor:sidebar.trailingAnchor constant:-12],
        [status.bottomAnchor constraintEqualToAnchor:sidebar.safeAreaLayoutGuide.bottomAnchor constant:-12]
    ]];
    self.remoteSourceTopConstraint = [sourceButtons.topAnchor constraintEqualToAnchor:self.workspaceControls.bottomAnchor constant:17];
    self.localSourceTopConstraint = [sourceButtons.topAnchor constraintEqualToAnchor:self.connectionModeControl.bottomAnchor constant:17];
    return sidebar;
}

- (NSView *)buildGenomeContent {
    NSView *content = [[NSView alloc] initWithFrame:NSZeroRect];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    NSVisualEffectView *toolbar = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    toolbar.material = NSVisualEffectMaterialHeaderView;
    toolbar.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    toolbar.state = NSVisualEffectStateActive;
    [content addSubview:toolbar];

    self.genomePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.genomePopup.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    NSArray<NSArray<NSString *> *> *genomes = @[
        @[@"Human · GRCh38 / hg38", @"hg38"], @[@"Human · GRCh37 / hg19", @"hg19"],
        @[@"Mouse · GRCm39 / mm39", @"mm39"], @[@"Mouse · GRCm38 / mm10", @"mm10"],
        @[@"Rat · mRatBN7.2 / rn7", @"rn7"], @[@"Zebrafish · GRCz11", @"danRer11"],
        @[@"Drosophila · dm6", @"dm6"], @[@"Yeast · sacCer3", @"sacCer3"]
    ];
    for (NSArray<NSString *> *entry in genomes) {
        [self.genomePopup addItemWithTitle:entry[0]];
        self.genomePopup.lastItem.representedObject = entry[1];
    }
    self.genomePopup.target = self;
    self.genomePopup.action = @selector(changeGenome:);
    self.genomePopup.toolTip = @"Reference assembly";

    self.locusField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.locusField.placeholderString = @"Gene, rsID, or genomic locus";
    self.locusField.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
    self.locusField.target = self;
    self.locusField.action = @selector(searchLocus:);
    [self.locusField setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.locusField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSButton *goButton = [NSButton buttonWithTitle:@"Go" target:self action:@selector(searchLocus:)];
    goButton.bezelStyle = NSBezelStyleRounded;
    NSButton *zoomOut = [self toolbarButton:@"minus.magnifyingglass" tip:@"Zoom out" action:@selector(zoomOut:)];
    NSButton *zoomIn = [self toolbarButton:@"plus.magnifyingglass" tip:@"Zoom in" action:@selector(zoomIn:)];
    self.highlightButton = [self toolbarButton:@"highlighter" tip:@"Highlight an interval" action:@selector(toggleHighlight:)];
    [self.highlightButton setButtonType:NSButtonTypeToggle];
    self.highlightColorWell = [[NSColorWell alloc] initWithFrame:NSZeroRect];
    self.highlightColorWell.color = [NSColor colorWithCalibratedRed:0.949 green:0.788 blue:0.298 alpha:1.0];
    self.highlightColorWell.target = self;
    self.highlightColorWell.action = @selector(changeHighlightColor:);
    self.highlightColorWell.toolTip = @"Highlight color";
    self.clearHighlightsButton = [self toolbarButton:@"eraser" tip:@"Clear highlights" action:@selector(clearHighlights:)];
    self.clearHighlightsButton.enabled = NO;
    NSButton *favorites = [self toolbarButton:@"star" tip:@"Favorites" action:@selector(openFavorites:)];
    NSButton *share = [self toolbarButton:@"square.and.arrow.up" tip:@"Create and copy share link" action:@selector(shareView:)];
    NSButton *exportButton = [self toolbarButton:@"camera" tip:@"Export PNG" action:@selector(exportPNG:)];
    self.reloadButton = [self toolbarButton:@"arrow.clockwise" tip:@"Reload from server" action:@selector(reloadOrStop:)];

    NSStackView *controls = [NSStackView stackViewWithViews:@[
        self.genomePopup, self.locusField, goButton, zoomOut, zoomIn,
        self.highlightButton, self.highlightColorWell, self.clearHighlightsButton,
        favorites, share, exportButton, self.reloadButton
    ]];
    controls.translatesAutoresizingMaskIntoConstraints = NO;
    controls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    controls.alignment = NSLayoutAttributeCenterY;
    controls.spacing = 7;
    [toolbar addSubview:controls];

    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.progressIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressIndicator.style = NSProgressIndicatorStyleBar;
    self.progressIndicator.indeterminate = NO;
    self.progressIndicator.minValue = 0;
    self.progressIndicator.maxValue = 1;
    self.progressIndicator.hidden = YES;
    [content addSubview:self.progressIndicator];

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = YES;
    [configuration.userContentController addScriptMessageHandler:self name:@"genomeCanvas"];
    self.webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.allowsMagnification = YES;
    [content addSubview:self.webView];

    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:content.topAnchor],
        [toolbar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [toolbar.heightAnchor constraintEqualToConstant:54],
        [controls.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor constant:12],
        [controls.trailingAnchor constraintEqualToAnchor:toolbar.trailingAnchor constant:-12],
        [controls.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [self.genomePopup.widthAnchor constraintEqualToConstant:177],
        [self.locusField.widthAnchor constraintGreaterThanOrEqualToConstant:190],
        [self.highlightColorWell.widthAnchor constraintEqualToConstant:31],
        [self.highlightColorWell.heightAnchor constraintEqualToConstant:27],
        [self.progressIndicator.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [self.progressIndicator.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.progressIndicator.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.progressIndicator.heightAnchor constraintEqualToConstant:2],
        [self.webView.topAnchor constraintEqualToAnchor:self.progressIndicator.bottomAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]
    ]];
    return content;
}

- (NSTextField *)sectionLabel:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (NSButton *)sidebarButton:(NSString *)title symbol:(NSString *)symbol action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeLarge;
    button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
    button.imagePosition = NSImageLeading;
    button.alignment = NSTextAlignmentLeft;
    [button.heightAnchor constraintEqualToConstant:36].active = YES;
    return button;
}

- (NSButton *)compactButton:(NSString *)symbol tip:(NSString *)tip action:(SEL)action {
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tip];
    NSButton *button = [NSButton buttonWithImage:image target:self action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.toolTip = tip;
    [button.widthAnchor constraintEqualToConstant:27].active = YES;
    [button.heightAnchor constraintEqualToConstant:27].active = YES;
    return button;
}

- (NSButton *)toolbarButton:(NSString *)symbol tip:(NSString *)tip action:(SEL)action {
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tip];
    NSButton *button = [NSButton buttonWithImage:image target:self action:action];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.toolTip = tip;
    [button.widthAnchor constraintEqualToConstant:32].active = YES;
    [button.heightAnchor constraintEqualToConstant:28].active = YES;
    return button;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self stopLocalBackend];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"genomeCanvas"];
}

- (void)dealloc {
    @try { [self.webView removeObserver:self forKeyPath:@"estimatedProgress"]; }
    @catch (__unused NSException *exception) {}
}

- (void)buildApplicationMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *applicationItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *applicationMenu = [[NSMenu alloc] initWithTitle:@"Genome Canvas"];
    [applicationMenu addItemWithTitle:@"About Genome Canvas" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [applicationMenu addItem:[NSMenuItem separatorItem]];
    self.localBackendMenuItem = [[NSMenuItem alloc] initWithTitle:@"Use Local Backend" action:@selector(useLocalBackend:) keyEquivalent:@""];
    self.localBackendMenuItem.target = self;
    [applicationMenu addItem:self.localBackendMenuItem];
    self.remoteServerMenuItem = [[NSMenuItem alloc] initWithTitle:@"Connect to Server…" action:@selector(editServerAddress:) keyEquivalent:@","];
    self.remoteServerMenuItem.target = self;
    [applicationMenu addItem:self.remoteServerMenuItem];
    [applicationMenu addItem:[NSMenuItem separatorItem]];
    [applicationMenu addItemWithTitle:@"Hide Genome Canvas" action:@selector(hide:) keyEquivalent:@"h"];
    [applicationMenu addItemWithTitle:@"Quit Genome Canvas" action:@selector(terminate:) keyEquivalent:@"q"];
    applicationItem.submenu = applicationMenu;
    [mainMenu addItem:applicationItem];

    NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    self.openFilesMenuItem = [[NSMenuItem alloc] initWithTitle:@"Open Server Files…" action:@selector(openServerFiles:) keyEquivalent:@"o"];
    self.openFilesMenuItem.target = self;
    [fileMenu addItem:self.openFilesMenuItem];
    NSMenuItem *publicData = [[NSMenuItem alloc] initWithTitle:@"Connect Public Data…" action:@selector(openPublicData:) keyEquivalent:@"d"];
    publicData.target = self;
    [fileMenu addItem:publicData];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *export = [[NSMenuItem alloc] initWithTitle:@"Export PNG…" action:@selector(exportPNG:) keyEquivalent:@"e"];
    export.target = self;
    export.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [fileMenu addItem:export];
    fileItem.submenu = fileMenu;
    [mainMenu addItem:fileItem];

    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = editMenu;
    [mainMenu addItem:editItem];

    NSMenuItem *viewItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    NSMenuItem *favorites = [[NSMenuItem alloc] initWithTitle:@"Favorites…" action:@selector(openFavorites:) keyEquivalent:@"s"];
    favorites.target = self;
    favorites.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [viewMenu addItem:favorites];
    NSMenuItem *reload = [[NSMenuItem alloc] initWithTitle:@"Reload Genome Canvas" action:@selector(reloadOrStop:) keyEquivalent:@"r"];
    reload.target = self;
    [viewMenu addItem:reload];
    viewItem.submenu = viewMenu;
    [mainMenu addItem:viewItem];
    [NSApp setMainMenu:mainMenu];
}

- (void)updateConnectionUI {
    self.connectionModeControl.selectedSegment = self.localMode ? 0 : 1;
    self.workspaceLabel.hidden = self.localMode;
    self.workspaceControls.hidden = self.localMode;
    [NSLayoutConstraint deactivateConstraints:@[self.remoteSourceTopConstraint, self.localSourceTopConstraint]];
    NSLayoutConstraint *sourceTopConstraint = self.localMode ? self.localSourceTopConstraint : self.remoteSourceTopConstraint;
    sourceTopConstraint.active = YES;
    self.filesButton.title = self.localMode ? @"Open Local Files" : @"Open Server Files";
    self.openFilesMenuItem.title = self.localMode ? @"Open Local Files…" : @"Open Server Files…";
    self.localBackendMenuItem.state = self.localMode ? NSControlStateValueOn : NSControlStateValueOff;
    self.remoteServerMenuItem.state = self.localMode ? NSControlStateValueOff : NSControlStateValueOn;
    self.window.subtitle = self.localMode ? @"Local genomics workbench" : @"Server-connected genomics workbench";
}

- (NSString *)localPythonPath {
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *candidate in @[@"/usr/bin/python3", @"/opt/homebrew/bin/python3", @"/usr/local/bin/python3"]) {
        if ([manager isExecutableFileAtPath:candidate]) return candidate;
    }
    return nil;
}

- (NSURL *)localApplicationSupportURL:(NSError **)error {
    NSURL *base = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL *directory = [base URLByAppendingPathComponent:@"Genome Canvas" isDirectory:YES];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    return directory;
}

- (void)showLocalBackendError:(NSString *)message {
    [self setStatus:@"Local backend unavailable" state:@"error"];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleCritical;
    alert.messageText = @"Local Backend Could Not Start";
    alert.informativeText = message ?: @"The bundled local backend could not be started.";
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)startLocalBackend {
    if (self.localServerTask.running) {
        if (self.localServerAddress.length) [self loadServerAddress:self.localServerAddress remember:NO];
        return;
    }

    NSURL *scriptURL = [[NSBundle mainBundle] URLForResource:@"server" withExtension:@"py" subdirectory:@"LocalBackend"];
    NSString *pythonPath = [self localPythonPath];
    if (!scriptURL || !pythonPath) {
        [self showLocalBackendError:@"The local backend resources or Python 3 runtime were not found. Install Xcode Command Line Tools, or connect to a Genome Canvas server instead."];
        return;
    }

    NSError *directoryError = nil;
    NSURL *supportURL = [self localApplicationSupportURL:&directoryError];
    if (!supportURL) {
        [self showLocalBackendError:directoryError.localizedDescription];
        return;
    }
    NSURL *readyURL = [supportURL URLByAppendingPathComponent:@"local-backend-ready.json"];
    NSURL *logURL = [supportURL URLByAppendingPathComponent:@"local-backend.log"];
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager removeItemAtURL:readyURL error:nil];
    [manager createFileAtPath:logURL.path contents:[NSData data] attributes:nil];
    self.localServerLogHandle = [NSFileHandle fileHandleForWritingAtPath:logURL.path];

    NSMutableDictionary<NSString *, NSString *> *environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
    environment[@"GENOME_CANVAS_LOCAL_MODE"] = @"1";
    environment[@"GENOME_CANVAS_STATE_DIR"] = supportURL.path;
    environment[@"GENOME_DATA_ROOTS"] = @"/";
    environment[@"PYTHONUNBUFFERED"] = @"1";

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:pythonPath];
    task.currentDirectoryURL = [scriptURL URLByDeletingLastPathComponent];
    task.arguments = @[scriptURL.path, @"--host", @"127.0.0.1", @"--port", @"0", @"--ready-file", readyURL.path];
    task.environment = environment;
    task.standardOutput = self.localServerLogHandle;
    task.standardError = self.localServerLogHandle;
    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *finishedTask) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.localServerTask != finishedTask) return;
            strongSelf.localServerTask = nil;
            if (strongSelf.localMode) [strongSelf showLocalBackendError:[NSString stringWithFormat:@"The local backend stopped unexpectedly. See %@", logURL.path]];
        });
    };
    self.localServerTask = task;
    [self setStatus:@"Starting local backend" state:@"busy"];
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        self.localServerTask = nil;
        [self showLocalBackendError:launchError.localizedDescription];
        return;
    }
    [self waitForLocalBackendReadyAtURL:readyURL attempt:0];
}

- (void)waitForLocalBackendReadyAtURL:(NSURL *)readyURL attempt:(NSInteger)attempt {
    if (!self.localMode || !self.localServerTask.running) return;
    NSData *data = [NSData dataWithContentsOfURL:readyURL];
    NSDictionary *payload = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSNumber *port = [payload isKindOfClass:[NSDictionary class]] ? payload[@"port"] : nil;
    if (port.integerValue > 0) {
        self.localServerAddress = [NSString stringWithFormat:@"http://127.0.0.1:%ld/?local=1", (long)port.integerValue];
        [self loadServerAddress:self.localServerAddress remember:NO];
        return;
    }
    if (attempt >= 100) {
        [self stopLocalBackend];
        [self showLocalBackendError:@"The local backend did not become ready within 10 seconds. See ~/Library/Application Support/Genome Canvas/local-backend.log."];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self waitForLocalBackendReadyAtURL:readyURL attempt:attempt + 1];
    });
}

- (void)stopLocalBackend {
    NSTask *task = self.localServerTask;
    self.localServerTask = nil;
    self.localServerAddress = nil;
    if (task.running) [task terminate];
    [self.localServerLogHandle closeFile];
    self.localServerLogHandle = nil;
}

- (void)activateLocalBackend {
    self.localMode = YES;
    [self updateConnectionUI];
    [self startLocalBackend];
}

- (void)connectToRemoteServer:(NSString *)address {
    if (![self normalizedURL:address]) {
        [self setStatus:@"Invalid server address" state:@"error"];
        [self updateConnectionUI];
        NSBeep();
        return;
    }
    [self stopLocalBackend];
    self.localMode = NO;
    [self updateConnectionUI];
    [self loadServerAddress:address remember:YES];
}

- (void)changeConnectionMode:(id)sender {
    if (self.connectionModeControl.selectedSegment == 0) [self activateLocalBackend];
    else [self editServerAddress:sender];
}

- (void)useLocalBackend:(id)sender { [self activateLocalBackend]; }

- (NSURL *)normalizedURL:(NSString *)value {
    NSString *candidate = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!candidate.length) return nil;
    if ([candidate rangeOfString:@"://"].location == NSNotFound) candidate = [@"http://" stringByAppendingString:candidate];
    NSURLComponents *components = [NSURLComponents componentsWithString:candidate];
    NSString *scheme = components.scheme.lowercaseString;
    if (!components.host.length || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return nil;
    if (!components.path.length || [components.path isEqualToString:@"/"]) components.path = @"/genome-canvas/";
    else if (![components.path hasSuffix:@"/"]) components.path = [components.path stringByAppendingString:@"/"];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        if (![item.name isEqualToString:@"desktop"]) [items addObject:item];
    }
    [items addObject:[NSURLQueryItem queryItemWithName:@"desktop" value:@"1"]];
    components.queryItems = items;
    return components.URL;
}

- (NSString *)storableAddressFromURL:(NSURL *)url {
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) if (![item.name isEqualToString:@"desktop"]) [items addObject:item];
    components.queryItems = items.count ? items : nil;
    return components.URL.absoluteString;
}

- (void)loadServerAddress:(NSString *)value remember:(BOOL)remember {
    NSURL *url = [self normalizedURL:value];
    if (!url) { [self setStatus:@"Invalid server address" state:@"error"]; NSBeep(); return; }
    if (remember) {
        self.serverAddress = [self storableAddressFromURL:url];
        [[NSUserDefaults standardUserDefaults] setObject:self.serverAddress forKey:GCServerDefaultsKey];
    }
    [self setStatus:@"Connecting" state:@"busy"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadRevalidatingCacheData timeoutInterval:30];
    [self.webView loadRequest:request];
}

- (void)setStatus:(NSString *)text state:(NSString *)state {
    self.statusLabel.stringValue = text.length ? text : @"Ready";
    if ([state isEqualToString:@"error"]) self.statusDot.textColor = [NSColor systemRedColor];
    else if ([state isEqualToString:@"busy"]) self.statusDot.textColor = [NSColor systemOrangeColor];
    else self.statusDot.textColor = [NSColor systemBlueColor];
}

- (NSString *)JSONFragment:(id)value {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value ?: [NSNull null] options:NSJSONWritingFragmentsAllowed error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"null";
}

- (void)callDesktopMethod:(NSString *)method arguments:(NSArray *)arguments {
    NSMutableArray<NSString *> *encoded = [NSMutableArray arrayWithCapacity:arguments.count];
    for (id argument in arguments) [encoded addObject:[self JSONFragment:argument]];
    NSString *script = [NSString stringWithFormat:@"(function(){const b=window.GenomeCanvasDesktop;return b&&b[%@](%@);})()", [self JSONFragment:method], [encoded componentsJoinedByString:@","]];
    [self.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error && error.code != WKErrorJavaScriptResultTypeIsUnsupported) [self setStatus:@"Desktop command failed" state:@"error"];
    }];
}

- (void)requestSnapshot {
    [self.webView evaluateJavaScript:@"window.GenomeCanvasDesktop && window.GenomeCanvasDesktop.snapshot()" completionHandler:^(id result, NSError *error) {
        if ([result isKindOfClass:[NSDictionary class]]) [self applySnapshot:(NSDictionary *)result];
    }];
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"genomeCanvas"] || ![message.body isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *payload = (NSDictionary *)message.body;
    if ([payload[@"type"] isEqualToString:@"share"]) {
        NSString *url = payload[@"url"];
        if (url.length) {
            NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
            [pasteboard clearContents];
            [pasteboard setString:url forType:NSPasteboardTypeString];
            [self setStatus:@"Share link copied" state:@"ready"];
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Share Link Copied";
            alert.informativeText = @"The LAN share link is ready on the clipboard.";
            [alert addButtonWithTitle:@"OK"];
            [alert beginSheetModalForWindow:self.window completionHandler:nil];
        }
        return;
    }
    [self applySnapshot:payload];
}

- (void)applySnapshot:(NSDictionary *)snapshot {
    NSArray *workspaceRecords = [snapshot[@"workspaces"] isKindOfClass:[NSArray class]] ? snapshot[@"workspaces"] : @[];
    if (![workspaceRecords isEqualToArray:self.workspaces]) {
        self.workspaces = workspaceRecords;
        [self.workspacePopup removeAllItems];
        if (!workspaceRecords.count) [self.workspacePopup addItemWithTitle:@"Choose Workspace…"];
        for (NSDictionary *workspace in workspaceRecords) {
            [self.workspacePopup addItemWithTitle:workspace[@"name"] ?: @"Workspace"];
            self.workspacePopup.lastItem.representedObject = workspace[@"id"];
        }
    }
    NSString *workspaceId = [snapshot[@"workspace"] isKindOfClass:[NSDictionary class]] ? snapshot[@"workspace"][@"id"] : nil;
    NSString *workspaceKind = [snapshot[@"workspace"] isKindOfClass:[NSDictionary class]] ? snapshot[@"workspace"][@"kind"] : nil;
    for (NSMenuItem *item in self.workspacePopup.itemArray) {
        if (workspaceId.length && [item.representedObject isEqual:workspaceId]) { [self.workspacePopup selectItem:item]; break; }
    }
    self.deleteWorkspaceButton.enabled = [workspaceKind isEqualToString:@"manual"];

    NSString *genome = [snapshot[@"genome"] isKindOfClass:[NSString class]] ? snapshot[@"genome"] : nil;
    if (genome.length) {
        NSMenuItem *found = nil;
        for (NSMenuItem *item in self.genomePopup.itemArray) if ([item.representedObject isEqual:genome]) { found = item; break; }
        if (!found) {
            [self.genomePopup addItemWithTitle:[NSString stringWithFormat:@"Custom · %@", genome]];
            self.genomePopup.lastItem.representedObject = genome;
            found = self.genomePopup.lastItem;
        }
        [self.genomePopup selectItem:found];
    }

    NSText *fieldEditor = [self.window fieldEditor:NO forObject:self.locusField];
    NSString *locus = [snapshot[@"locus"] isKindOfClass:[NSString class]] ? snapshot[@"locus"] : @"";
    if (locus.length && self.window.firstResponder != fieldEditor) self.locusField.stringValue = locus;

    NSArray *trackRecords = [snapshot[@"tracks"] isKindOfClass:[NSArray class]] ? snapshot[@"tracks"] : @[];
    if (![trackRecords isEqualToArray:self.tracks]) {
        self.tracks = trackRecords;
        [self.trackTable reloadData];
    }
    self.trackCountLabel.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)self.tracks.count];
    self.removeTrackButton.enabled = self.trackTable.selectedRow >= 0;
    self.highlightButton.state = [snapshot[@"highlightMode"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.clearHighlightsButton.enabled = [snapshot[@"highlightCount"] integerValue] > 0;
    NSString *color = snapshot[@"highlightColor"];
    if ([color isKindOfClass:[NSString class]]) self.highlightColorWell.color = [self colorFromHex:color];
    NSString *status = [snapshot[@"status"] isKindOfClass:[NSString class]] ? snapshot[@"status"] : @"Ready";
    NSString *mode = [snapshot[@"statusMode"] isKindOfClass:[NSString class]] ? snapshot[@"statusMode"] : @"ready";
    [self setStatus:status state:mode];
}

- (NSColor *)colorFromHex:(NSString *)hex {
    double red = 0, green = 0, blue = 0;
    if ([hex hasPrefix:@"rgb"] && sscanf(hex.UTF8String, "rgb(%lf, %lf, %lf", &red, &green, &blue) == 3) {
        return [NSColor colorWithSRGBRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:1.0];
    }
    NSString *value = [hex stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"#"]];
    unsigned int rgb = 0;
    if (value.length != 6 || ![[NSScanner scannerWithString:value] scanHexInt:&rgb]) return [NSColor systemBlueColor];
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xff) / 255.0 green:((rgb >> 8) & 0xff) / 255.0 blue:(rgb & 0xff) / 255.0 alpha:1.0];
}

- (NSString *)hexFromColor:(NSColor *)color {
    NSColor *rgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: color;
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)round(rgb.redComponent * 255), (int)round(rgb.greenComponent * 255), (int)round(rgb.blueComponent * 255)];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.tracks.count; }

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"TrackCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"TrackCell";
        NSView *swatch = [[NSView alloc] initWithFrame:NSZeroRect];
        swatch.translatesAutoresizingMaskIntoConstraints = NO;
        swatch.wantsLayer = YES;
        swatch.layer.cornerRadius = 3;
        swatch.identifier = @"TrackSwatch";
        NSTextField *name = [NSTextField labelWithString:@""];
        name.translatesAutoresizingMaskIntoConstraints = NO;
        name.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
        name.lineBreakMode = NSLineBreakByTruncatingTail;
        name.identifier = @"TrackName";
        NSTextField *meta = [NSTextField labelWithString:@""];
        meta.translatesAutoresizingMaskIntoConstraints = NO;
        meta.font = [NSFont systemFontOfSize:9 weight:NSFontWeightMedium];
        meta.textColor = [NSColor secondaryLabelColor];
        meta.identifier = @"TrackMeta";
        NSImageView *grip = [[NSImageView alloc] initWithFrame:NSZeroRect];
        grip.translatesAutoresizingMaskIntoConstraints = NO;
        grip.image = [NSImage imageWithSystemSymbolName:@"line.3.horizontal" accessibilityDescription:@"Drag to reorder"];
        grip.contentTintColor = [NSColor tertiaryLabelColor];
        [cell addSubview:swatch]; [cell addSubview:name]; [cell addSubview:meta]; [cell addSubview:grip];
        [NSLayoutConstraint activateConstraints:@[
            [swatch.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8],
            [swatch.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [swatch.widthAnchor constraintEqualToConstant:6], [swatch.heightAnchor constraintEqualToConstant:34],
            [name.leadingAnchor constraintEqualToAnchor:swatch.trailingAnchor constant:10],
            [name.trailingAnchor constraintLessThanOrEqualToAnchor:grip.leadingAnchor constant:-6],
            [name.topAnchor constraintEqualToAnchor:cell.topAnchor constant:9],
            [meta.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
            [meta.trailingAnchor constraintLessThanOrEqualToAnchor:grip.leadingAnchor constant:-6],
            [meta.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:3],
            [grip.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-7],
            [grip.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [grip.widthAnchor constraintEqualToConstant:17], [grip.heightAnchor constraintEqualToConstant:17]
        ]];
    }
    NSDictionary *track = self.tracks[row];
    NSView *swatch = nil;
    NSTextField *nameField = nil;
    NSTextField *metaField = nil;
    for (NSView *subview in cell.subviews) {
        if ([subview.identifier isEqualToString:@"TrackSwatch"]) swatch = subview;
        if ([subview.identifier isEqualToString:@"TrackName"]) nameField = (NSTextField *)subview;
        if ([subview.identifier isEqualToString:@"TrackMeta"]) metaField = (NSTextField *)subview;
    }
    swatch.layer.backgroundColor = [self colorFromHex:track[@"color"] ?: @"#71808A"].CGColor;
    nameField.stringValue = track[@"name"] ?: @"Untitled track";
    metaField.stringValue = [track[@"format"] ?: @"track" uppercaseString];
    return cell;
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    [item setString:[NSString stringWithFormat:@"%ld", (long)row] forType:GCTrackRowPasteboardType];
    return item;
}

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation {
    [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation {
    NSString *value = [info.draggingPasteboard stringForType:GCTrackRowPasteboardType];
    NSInteger source = value.integerValue;
    NSInteger target = row;
    if (source < target) target -= 1;
    target = MAX(0, MIN((NSInteger)self.tracks.count - 1, target));
    if (source < 0 || source >= (NSInteger)self.tracks.count || source == target) return NO;
    NSMutableArray *updated = [self.tracks mutableCopy];
    NSDictionary *moved = updated[source];
    [updated removeObjectAtIndex:source];
    [updated insertObject:moved atIndex:target];
    self.tracks = updated;
    [tableView reloadData];
    [tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:target] byExtendingSelection:NO];
    [self callDesktopMethod:@"moveTrack" arguments:@[@(source), @(target)]];
    return YES;
}

- (void)trackSelectionChanged:(id)sender { self.removeTrackButton.enabled = self.trackTable.selectedRow >= 0; }

- (NSDictionary *)selectedWorkspaceRecord {
    NSString *workspaceId = self.workspacePopup.selectedItem.representedObject;
    for (NSDictionary *workspace in self.workspaces) if ([workspace[@"id"] isEqual:workspaceId]) return workspace;
    return nil;
}

- (void)changeWorkspace:(id)sender {
    NSDictionary *workspace = [self selectedWorkspaceRecord];
    self.deleteWorkspaceButton.enabled = [workspace[@"kind"] isEqualToString:@"manual"];
    NSString *workspaceId = workspace[@"id"];
    if (workspaceId) [self callDesktopMethod:@"selectWorkspace" arguments:@[workspaceId]];
}

- (void)createWorkspace:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Create Temporary Project";
    alert.informativeText = @"This creates an independent workspace with its own Favorites and a default /nfs file location.";
    [alert addButtonWithTitle:@"Create and Enter"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *input = [NSTextField textFieldWithString:@""];
    input.placeholderString = @"Project name";
    input.frame = NSMakeRect(0, 0, 340, 26);
    alert.accessoryView = input;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        NSString *name = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (result == NSAlertFirstButtonReturn && name.length) [self callDesktopMethod:@"createWorkspace" arguments:@[name]];
    }];
}

- (void)deleteWorkspace:(id)sender {
    NSDictionary *workspace = [self selectedWorkspaceRecord];
    if (![workspace[@"kind"] isEqualToString:@"manual"]) { NSBeep(); return; }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = [NSString stringWithFormat:@"Delete project “%@”?", workspace[@"name"] ?: @"Project"];
    alert.informativeText = @"The project entry will be removed. Server data under /nfs and saved Favorite files are not deleted.";
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSAlertFirstButtonReturn && workspace[@"id"]) [self callDesktopMethod:@"deleteWorkspace" arguments:@[workspace[@"id"]]];
    }];
}

- (void)manageWorkspaces:(id)sender { [self callDesktopMethod:@"openWorkspace" arguments:@[]]; }
- (void)changeGenome:(id)sender { id genome = self.genomePopup.selectedItem.representedObject; if (genome) [self callDesktopMethod:@"selectGenome" arguments:@[genome]]; }
- (void)searchLocus:(id)sender { if (self.locusField.stringValue.length) [self callDesktopMethod:@"search" arguments:@[self.locusField.stringValue]]; }
- (void)zoomIn:(id)sender { [self callDesktopMethod:@"zoomIn" arguments:@[]]; }
- (void)zoomOut:(id)sender { [self callDesktopMethod:@"zoomOut" arguments:@[]]; }
- (void)toggleHighlight:(id)sender { [self callDesktopMethod:@"setHighlight" arguments:@[@(self.highlightButton.state == NSControlStateValueOn)]]; }
- (void)changeHighlightColor:(id)sender { [self callDesktopMethod:@"setHighlightColor" arguments:@[[self hexFromColor:self.highlightColorWell.color]]]; }
- (void)clearHighlights:(id)sender { [self callDesktopMethod:@"clearHighlights" arguments:@[]]; }
- (void)openServerFiles:(id)sender { [self callDesktopMethod:@"openServerFiles" arguments:@[]]; }
- (void)openPublicData:(id)sender { [self callDesktopMethod:@"openPublicData" arguments:@[]]; }
- (void)openCustomReference:(id)sender { [self callDesktopMethod:@"openCustomReference" arguments:@[]]; }
- (void)openFavorites:(id)sender { [self callDesktopMethod:@"openFavorites" arguments:@[]]; }
- (void)shareView:(id)sender { [self callDesktopMethod:@"share" arguments:@[]]; }
- (void)exportPNG:(id)sender { [self callDesktopMethod:@"exportPNG" arguments:@[]]; }
- (void)removeSelectedTrack:(id)sender { NSInteger row = self.trackTable.selectedRow; if (row >= 0) [self callDesktopMethod:@"removeTrack" arguments:@[@(row)]]; }

- (void)editServerAddress:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Connect to Genome Canvas Server";
    alert.informativeText = @"Enter a LAN server address. The local backend will stop after the connection is accepted.";
    [alert addButtonWithTitle:@"Connect"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *input = [NSTextField textFieldWithString:self.serverAddress ?: GCDefaultServerAddress];
    input.frame = NSMakeRect(0, 0, 390, 26);
    alert.accessoryView = input;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSAlertFirstButtonReturn) [self connectToRemoteServer:input.stringValue];
        else [self updateConnectionUI];
    }];
}

- (void)reloadOrStop:(id)sender {
    if (self.webView.loading) { [self.webView stopLoading]; [self setStatus:@"Stopped" state:@"ready"]; }
    else { [self setStatus:@"Loading" state:@"busy"]; [self.webView reloadFromOrigin]; }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"estimatedProgress"]) {
        self.progressIndicator.doubleValue = self.webView.estimatedProgress;
        self.progressIndicator.hidden = !self.webView.loading;
        NSString *symbol = self.webView.loading ? @"xmark" : @"arrow.clockwise";
        self.reloadButton.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:@"Reload or stop"];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation { [self setStatus:@"Loading" state:@"busy"]; self.progressIndicator.hidden = NO; }
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.progressIndicator.hidden = YES;
    self.window.title = @"Genome Canvas";
    [self setStatus:@"Preparing canvas" state:@"busy"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self requestSnapshot]; });
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error { [self showNavigationError:error]; }
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error { [self showNavigationError:error]; }
- (void)showNavigationError:(NSError *)error { if (error.code != NSURLErrorCancelled) { [self setStatus:@"Server unavailable" state:@"error"]; self.statusLabel.toolTip = error.localizedDescription; self.progressIndicator.hidden = YES; } }
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView { [self setStatus:@"Canvas process stopped" state:@"error"]; }

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (navigationAction.shouldPerformDownload) { decisionHandler(WKNavigationActionPolicyDownload); return; }
    NSURL *url = navigationAction.request.URL;
    NSString *scheme = url.scheme.lowercaseString;
    NSSet *internalSchemes = [NSSet setWithArray:@[@"http", @"https", @"blob", @"about"]];
    if (scheme.length && ![internalSchemes containsObject:scheme]) { [[NSWorkspace sharedWorkspace] openURL:url]; decisionHandler(WKNavigationActionPolicyCancel); return; }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    NSString *disposition = @"";
    if ([navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]) disposition = [[(NSHTTPURLResponse *)navigationResponse.response valueForHTTPHeaderField:@"Content-Disposition"] lowercaseString] ?: @"";
    decisionHandler(!navigationResponse.canShowMIMEType || [disposition containsString:@"attachment"] ? WKNavigationResponsePolicyDownload : WKNavigationResponsePolicyAllow);
}
- (void)webView:(WKWebView *)webView navigationAction:(WKNavigationAction *)navigationAction didBecomeDownload:(WKDownload *)download { download.delegate = self; }
- (void)webView:(WKWebView *)webView navigationResponse:(WKNavigationResponse *)navigationResponse didBecomeDownload:(WKDownload *)download { download.delegate = self; }

- (void)download:(WKDownload *)download decideDestinationUsingResponse:(NSURLResponse *)response suggestedFilename:(NSString *)suggestedFilename completionHandler:(void (^)(NSURL * _Nullable destination))completionHandler {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = suggestedFilename;
    panel.canCreateDirectories = YES;
    panel.title = @"Save Genome Canvas File";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !panel.URL) { completionHandler(nil); return; }
        NSURL *destination = panel.URL;
        if ([[NSFileManager defaultManager] fileExistsAtPath:destination.path]) [[NSFileManager defaultManager] removeItemAtURL:destination error:nil];
        [self.downloadDestinations setObject:destination forKey:download];
        [self setStatus:@"Downloading" state:@"busy"];
        completionHandler(destination);
    }];
}
- (void)downloadDidFinish:(WKDownload *)download { NSURL *destination = [self.downloadDestinations objectForKey:download]; [self.downloadDestinations removeObjectForKey:download]; [self setStatus:(destination.lastPathComponent.length ? [@"Saved " stringByAppendingString:destination.lastPathComponent] : @"Download complete") state:@"ready"]; }
- (void)download:(WKDownload *)download didFailWithError:(NSError *)error resumeData:(NSData *)resumeData { [self.downloadDestinations removeObjectForKey:download]; [self setStatus:@"Download failed" state:@"error"]; self.statusLabel.toolTip = error.localizedDescription; }

- (void)webView:(WKWebView *)webView runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSArray<NSURL *> * _Nullable URLs))completionHandler {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection;
    panel.canChooseDirectories = parameters.allowsDirectories;
    panel.canChooseFiles = YES;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) { completionHandler(result == NSModalResponseOK ? panel.URLs : nil); }];
}
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures { if (!navigationAction.targetFrame) [webView loadRequest:navigationAction.request]; return nil; }
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler { NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = @"Genome Canvas"; alert.informativeText = message; [alert addButtonWithTitle:@"OK"]; [alert beginSheetModalForWindow:self.window completionHandler:^(__unused NSModalResponse result) { completionHandler(); }]; }
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL result))completionHandler { NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = @"Genome Canvas"; alert.informativeText = message; [alert addButtonWithTitle:@"Continue"]; [alert addButtonWithTitle:@"Cancel"]; [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) { completionHandler(result == NSAlertFirstButtonReturn); }]; }
- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSString * _Nullable result))completionHandler { NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = @"Genome Canvas"; alert.informativeText = prompt; [alert addButtonWithTitle:@"OK"]; [alert addButtonWithTitle:@"Cancel"]; NSTextField *input = [NSTextField textFieldWithString:defaultText ?: @""]; input.frame = NSMakeRect(0, 0, 320, 24); alert.accessoryView = input; [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) { completionHandler(result == NSAlertFirstButtonReturn ? input.stringValue : nil); }]; }

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        application.activationPolicy = NSApplicationActivationPolicyRegular;
        GCAppDelegate *delegate = [[GCAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
