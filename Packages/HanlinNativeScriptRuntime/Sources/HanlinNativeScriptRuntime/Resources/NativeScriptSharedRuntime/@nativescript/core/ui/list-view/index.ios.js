const __UI_USE_EXTERNAL_RENDERER__ = globalThis.__UI_USE_EXTERNAL_RENDERER__ !== undefined ? globalThis.__UI_USE_EXTERNAL_RENDERER__ : false;
import { ListViewBase, separatorColorProperty, itemTemplatesProperty, iosEstimatedRowHeightProperty, stickyHeaderProperty, stickyHeaderTemplateProperty, stickyHeaderHeightProperty, sectionedProperty, showSearchProperty, searchAutoHideProperty, iosSearchInsetBehaviorProperty } from './list-view-common';
import { View } from '../core/view';
import { Length } from '../styling/length-shared';
import { Observable } from '../../data/observable';
import { Color } from '../../color';
import { layout } from '../../utils';
import { SDK_VERSION } from '../../utils/constants';
import { StackLayout } from '../layouts/stack-layout';
import { ProxyViewContainer } from '../proxy-view-container';
import { profile } from '../../profiling';
import { Trace } from '../../trace';
import { Builder } from '../builder';
import { Label } from '../label';
import { isFunction } from '../../utils/types';
export * from './list-view-common';
const ITEMLOADING = ListViewBase.itemLoadingEvent;
const LOADMOREITEMS = ListViewBase.loadMoreItemsEvent;
const ITEMTAP = ListViewBase.itemTapEvent;
const DEFAULT_HEIGHT = 44;
const infinity = layout.makeMeasureSpec(0, layout.UNSPECIFIED);
var ListViewCell = (function (_super) {
    __extends(ListViewCell, _super);
    function ListViewCell() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    ListViewCell.initWithEmptyBackground = function () {
        var cell = ListViewCell.new();
        cell.backgroundColor = UIColor.clearColor;
        return cell;
    };
    ListViewCell.prototype.initWithStyleReuseIdentifier = function (style, reuseIdentifier) {
        var cell = _super.prototype.initWithStyleReuseIdentifier.call(this, style, reuseIdentifier);
        cell.backgroundColor = UIColor.clearColor;
        return cell;
    };
    ListViewCell.prototype.willMoveToSuperview = function (newSuperview) {
        var parent = (this.view ? this.view.parent : null);
        if (parent && !newSuperview) {
            parent._removeContainer(this);
        }
    };
    Object.defineProperty(ListViewCell.prototype, "view", {
        get: function () {
            return this.owner ? this.owner.deref() : null;
        },
        enumerable: true,
        configurable: true
    });
    return ListViewCell;
}(UITableViewCell));
var ListViewHeaderCell = (function (_super) {
    __extends(ListViewHeaderCell, _super);
    function ListViewHeaderCell() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    ListViewHeaderCell.initWithEmptyBackground = function () {
        var cell = ListViewHeaderCell.new();
        cell.backgroundColor = UIColor.clearColor;
        return cell;
    };
    ListViewHeaderCell.prototype.initWithReuseIdentifier = function (reuseIdentifier) {
        var cell = _super.prototype.initWithReuseIdentifier.call(this, reuseIdentifier);
        cell.backgroundColor = UIColor.clearColor;
        return cell;
    };
    ListViewHeaderCell.prototype.willMoveToSuperview = function (newSuperview) {
        var parent = (this.view ? this.view.parent : null);
        if (parent && !newSuperview) {
            parent._removeHeaderContainer(this);
        }
    };
    Object.defineProperty(ListViewHeaderCell.prototype, "view", {
        get: function () {
            return this.owner ? this.owner.deref() : null;
        },
        enumerable: true,
        configurable: true
    });
    return ListViewHeaderCell;
}(UITableViewHeaderFooterView));
function notifyForItemAtIndex(listView, cell, view, eventName, indexPath) {
    const args = {
        eventName: eventName,
        object: listView,
        index: indexPath.row,
        section: indexPath.section,
        view: view,
        ios: cell,
        android: undefined,
    };
    listView.notify(args);
    return args;
}
var DataSource = (function (_super) {
    __extends(DataSource, _super);
    function DataSource() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    DataSource.initWithOwner = function (owner) {
        var dataSource = DataSource.new();
        dataSource._owner = owner;
        return dataSource;
    };
    DataSource.prototype.numberOfSectionsInTableView = function (tableView) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (!owner) {
            return 1;
        }
        var sections = owner._getSectionCount();
        if (Trace.isEnabled()) {
            Trace.write("ListView: numberOfSections = ".concat(sections, " (sectioned: ").concat(owner.sectioned, ")"), Trace.categories.Debug);
        }
        return sections;
    };
    DataSource.prototype.tableViewNumberOfRowsInSection = function (tableView, section) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (!owner) {
            return 0;
        }
        var sectionItems = owner._getItemsInSection(section);
        var rowCount = sectionItems ? sectionItems.length : 0;
        if (Trace.isEnabled()) {
            Trace.write("ListView: numberOfRows in section ".concat(section, " = ").concat(rowCount), Trace.categories.Debug);
        }
        return rowCount;
    };
    DataSource.prototype.tableViewCellForRowAtIndexPath = function (tableView, indexPath) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        var cell;
        if (owner) {
            var template = owner.sectioned ? owner._getItemTemplateInSection(indexPath.section, indexPath.row) : owner._getItemTemplate(indexPath.row);
            cell = (tableView.dequeueReusableCellWithIdentifier(template.key) || ListViewCell.initWithEmptyBackground());
            owner._prepareCell(cell, indexPath);
            var cellView = cell.view;
            if (cellView && cellView.isLayoutRequired) {
                var width = layout.getMeasureSpecSize(owner.widthMeasureSpec);
                var rowHeight = owner._effectiveRowHeight;
                var cellHeight = rowHeight > 0 ? rowHeight : owner.getHeight(indexPath.row, indexPath.section);
                cellView.iosOverflowSafeAreaEnabled = false;
                View.layoutChild(owner, cellView, 0, 0, width, cellHeight);
            }
        }
        else {
            cell = ListViewCell.initWithEmptyBackground();
        }
        return cell;
    };
    DataSource.ObjCProtocols = [UITableViewDataSource];
    return DataSource;
}(NSObject));
var UITableViewDelegateImpl = (function (_super) {
    __extends(UITableViewDelegateImpl, _super);
    function UITableViewDelegateImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UITableViewDelegateImpl.initWithOwner = function (owner) {
        var delegate = UITableViewDelegateImpl.new();
        delegate._owner = owner;
        delegate._measureCellMap = new Map();
        return delegate;
    };
    UITableViewDelegateImpl.prototype.tableViewWillDisplayCellForRowAtIndexPath = function (tableView, cell, indexPath) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner && indexPath.row === owner.items.length - 1) {
            owner.notify({
                eventName: LOADMOREITEMS,
                object: owner,
            });
        }
    };
    UITableViewDelegateImpl.prototype.tableViewWillSelectRowAtIndexPath = function (tableView, indexPath) {
        var _a;
        var cell = tableView.cellForRowAtIndexPath(indexPath);
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            notifyForItemAtIndex(owner, cell, cell.view, ITEMTAP, indexPath);
        }
        return indexPath;
    };
    UITableViewDelegateImpl.prototype.tableViewDidSelectRowAtIndexPath = function (tableView, indexPath) {
        tableView.deselectRowAtIndexPathAnimated(indexPath, true);
        return indexPath;
    };
    UITableViewDelegateImpl.prototype.tableViewHeightForRowAtIndexPath = function (tableView, indexPath) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (!owner) {
            return tableView.estimatedRowHeight;
        }
        var height = owner.getHeight(indexPath.row, indexPath.section);
        if (height === undefined) {
            var template = owner.sectioned ? owner._getItemTemplateInSection(indexPath.section, indexPath.row) : owner._getItemTemplate(indexPath.row);
            var cell = this._measureCellMap.get(template.key);
            if (!cell) {
                cell = tableView.dequeueReusableCellWithIdentifier(template.key) || ListViewCell.initWithEmptyBackground();
                this._measureCellMap.set(template.key, cell);
            }
            height = owner._prepareCell(cell, indexPath);
        }
        return layout.toDeviceIndependentPixels(height);
    };
    UITableViewDelegateImpl.prototype.tableViewViewForHeaderInSection = function (tableView, section) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (!owner || !owner.stickyHeader || !owner.stickyHeaderTemplate) {
            if (Trace.isEnabled()) {
                Trace.write("ListView: No sticky header (stickyHeader: ".concat(owner === null || owner === void 0 ? void 0 : owner.stickyHeader, ", hasTemplate: ").concat(!!(owner === null || owner === void 0 ? void 0 : owner.stickyHeaderTemplate), ")"), Trace.categories.Debug);
            }
            return null;
        }
        if (Trace.isEnabled()) {
            Trace.write("ListView: Creating sticky header", Trace.categories.Debug);
        }
        var headerReuseIdentifier = "stickyHeader";
        var headerCell = tableView.dequeueReusableHeaderFooterViewWithIdentifier(headerReuseIdentifier);
        if (!headerCell) {
            headerCell = ListViewHeaderCell.alloc().initWithReuseIdentifier(headerReuseIdentifier);
            headerCell.backgroundColor = UIColor.clearColor;
        }
        owner._prepareHeader(headerCell, section);
        return headerCell;
    };
    UITableViewDelegateImpl.prototype.tableViewHeightForHeaderInSection = function (tableView, section) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (!owner || !owner.stickyHeader) {
            return 0;
        }
        var height;
        if (owner.stickyHeaderHeight === "auto") {
            height = 44;
        }
        else {
            height = layout.toDeviceIndependentPixels(Length.toDevicePixels(owner.stickyHeaderHeight, 44));
        }
        if (Trace.isEnabled()) {
            Trace.write("ListView: Sticky header height: ".concat(height), Trace.categories.Debug);
        }
        return height;
    };
    UITableViewDelegateImpl.ObjCProtocols = [UITableViewDelegate];
    return UITableViewDelegateImpl;
}(NSObject));
var UITableViewRowHeightDelegateImpl = (function (_super) {
    __extends(UITableViewRowHeightDelegateImpl, _super);
    function UITableViewRowHeightDelegateImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UITableViewRowHeightDelegateImpl.initWithOwner = function (owner) {
        var delegate = UITableViewRowHeightDelegateImpl.new();
        delegate._owner = owner;
        return delegate;
    };
    UITableViewRowHeightDelegateImpl.prototype.tableViewWillDisplayCellForRowAtIndexPath = function (tableView, cell, indexPath) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner && indexPath.row === owner.items.length - 1) {
            owner.notify({
                eventName: LOADMOREITEMS,
                object: owner,
            });
        }
    };
    UITableViewRowHeightDelegateImpl.prototype.tableViewWillSelectRowAtIndexPath = function (tableView, indexPath) {
        var _a;
        var cell = tableView.cellForRowAtIndexPath(indexPath);
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            notifyForItemAtIndex(owner, cell, cell.view, ITEMTAP, indexPath);
        }
        return indexPath;
    };
    UITableViewRowHeightDelegateImpl.prototype.tableViewDidSelectRowAtIndexPath = function (tableView, indexPath) {
        tableView.deselectRowAtIndexPathAnimated(indexPath, true);
        return indexPath;
    };
    UITableViewRowHeightDelegateImpl.prototype.tableViewHeightForRowAtIndexPath = function (tableView, indexPath) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (!owner) {
            return tableView.estimatedRowHeight;
        }
        return layout.toDeviceIndependentPixels(owner._effectiveRowHeight);
    };
    UITableViewRowHeightDelegateImpl.prototype.tableViewViewForHeaderInSection = function (tableView, section) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (!owner || !owner.stickyHeader || !owner.stickyHeaderTemplate) {
            if (Trace.isEnabled()) {
                Trace.write("ListView: No sticky header (stickyHeader: ".concat(owner === null || owner === void 0 ? void 0 : owner.stickyHeader, ", hasTemplate: ").concat(!!(owner === null || owner === void 0 ? void 0 : owner.stickyHeaderTemplate), ")"), Trace.categories.Debug);
            }
            return null;
        }
        if (Trace.isEnabled()) {
            Trace.write("ListView: Creating sticky header", Trace.categories.Debug);
        }
        var headerReuseIdentifier = "stickyHeader";
        var headerCell = tableView.dequeueReusableHeaderFooterViewWithIdentifier(headerReuseIdentifier);
        if (!headerCell) {
            headerCell = ListViewHeaderCell.alloc().initWithReuseIdentifier(headerReuseIdentifier);
            headerCell.backgroundColor = UIColor.clearColor;
        }
        owner._prepareHeader(headerCell, section);
        return headerCell;
    };
    UITableViewRowHeightDelegateImpl.prototype.tableViewHeightForHeaderInSection = function (tableView, section) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (!owner || !owner.stickyHeader) {
            return 0;
        }
        var height;
        if (owner.stickyHeaderHeight === "auto") {
            height = 44;
        }
        else {
            height = layout.toDeviceIndependentPixels(Length.toDevicePixels(owner.stickyHeaderHeight, 44));
        }
        if (Trace.isEnabled()) {
            Trace.write("ListView: Sticky header height: ".concat(height), Trace.categories.Debug);
        }
        return height;
    };
    UITableViewRowHeightDelegateImpl.ObjCProtocols = [UITableViewDelegate];
    return UITableViewRowHeightDelegateImpl;
}(NSObject));
var UISearchResultsUpdatingImpl = (function (_super) {
    __extends(UISearchResultsUpdatingImpl, _super);
    function UISearchResultsUpdatingImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UISearchResultsUpdatingImpl.initWithOwner = function (owner) {
        var handler = UISearchResultsUpdatingImpl.new();
        handler._owner = owner;
        return handler;
    };
    UISearchResultsUpdatingImpl.prototype.updateSearchResultsForSearchController = function (searchController) {
        var owner = this._owner ? this._owner.get() : null;
        if (!owner) {
            return;
        }
        var searchText = searchController.searchBar.text || "";
        owner._isSearchActive = searchController.active;
        var eventData = {
            eventName: ListViewBase.searchChangeEvent,
            object: owner,
            text: searchText,
            ios: searchController,
        };
        owner.notify(eventData);
    };
    UISearchResultsUpdatingImpl.ObjCProtocols = [UISearchResultsUpdating];
    return UISearchResultsUpdatingImpl;
}(NSObject));
export class ListView extends ListViewBase {
    constructor() {
        super();
        this._isSearchActive = false;
        this.widthMeasureSpec = 0;
        this._map = new Map();
        this._headerMap = new Map();
        this._heights = new Array();
    }
    createNativeView() {
        return UITableView.new();
    }
    initNativeView() {
        super.initNativeView();
        const nativeView = this.nativeViewProtected;
        nativeView.registerClassForCellReuseIdentifier(ListViewCell.class(), this._defaultTemplate.key);
        nativeView.registerClassForHeaderFooterViewReuseIdentifier(ListViewHeaderCell.class(), 'stickyHeader');
        nativeView.estimatedRowHeight = DEFAULT_HEIGHT;
        nativeView.rowHeight = UITableViewAutomaticDimension;
        nativeView.dataSource = this._dataSource = DataSource.initWithOwner(new WeakRef(this));
        this._delegate = UITableViewDelegateImpl.initWithOwner(new WeakRef(this));
        // Control section header top padding (iOS 15+)
        if (nativeView.respondsToSelector('setSectionHeaderTopPadding:')) {
            if (!this.stickyHeaderTopPadding) {
                nativeView.sectionHeaderTopPadding = 0;
            }
            // When stickyHeaderTopPadding is true, don't set the property to use iOS default
        }
        this._setNativeClipToBounds();
    }
    disposeNativeView() {
        this._cleanupSearchController();
        this._delegate = null;
        this._dataSource = null;
        super.disposeNativeView();
    }
    _setupSearchController() {
        if (!this.showSearch || this._searchController) {
            return; // Already setup or not needed
        }
        // 1. Create UISearchController with nil (show results in this table)
        this._searchController = UISearchController.alloc().initWithSearchResultsController(null);
        this._searchDelegate = UISearchResultsUpdatingImpl.initWithOwner(new WeakRef(this));
        // 2. Tell it who will update results
        this._searchController.searchResultsUpdater = this._searchDelegate;
        // 3. Critical: Don't dim or obscure the table, and prevent extra content
        this._searchController.obscuresBackgroundDuringPresentation = false;
        this._searchController.dimsBackgroundDuringPresentation = false;
        this._searchController.hidesNavigationBarDuringPresentation = false;
        // 4. Placeholder text and styling
        this._searchController.searchBar.placeholder = 'Search';
        this._searchController.searchBar.searchBarStyle = 2 /* UISearchBarStyle.Minimal */;
        // 5. CRITICAL: Proper presentation context setup
        const viewController = this._getViewController();
        if (viewController) {
            viewController.definesPresentationContext = true;
            viewController.providesPresentationContextTransitionStyle = true;
            // 6a. If we're in a UINavigationController (iOS 11+)...
            if (SDK_VERSION >= 11.0 && viewController.navigationItem) {
                viewController.navigationItem.searchController = this._searchController;
                // Set auto-hide behavior based on searchAutoHide property
                viewController.navigationItem.hidesSearchBarWhenScrolling = this.searchAutoHide;
                // Optional: Enable large titles for better auto-hide effect when searchAutoHide is true
                // if (this.searchAutoHide && viewController.navigationController && viewController.navigationController.navigationBar) {
                // 	// Only set large titles if not already configured
                // 	if (!viewController.navigationController.navigationBar.prefersLargeTitles) {
                // 		viewController.navigationController.navigationBar.prefersLargeTitles = true;
                // 	}
                // 	// Set large title display mode for this specific view controller
                // 	if (viewController.navigationItem.largeTitleDisplayMode === UINavigationItemLargeTitleDisplayMode.Automatic) {
                // 		viewController.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayMode.Always;
                // 	}
                // }
            }
            else {
                // 6b. Fallback: put it at the top of our table
                this.nativeViewProtected.tableHeaderView = this._searchController.searchBar;
            }
        }
        else {
            // Fallback: no view controller found, use table header
            this.nativeViewProtected.tableHeaderView = this._searchController.searchBar;
        }
        // 7. Ensure search bar is properly sized and prevent content inset issues
        this._searchController.searchBar.sizeToFit();
        // 8. Pick a sensible content-inset-adjustment behavior.
        // - If `iosSearchInsetBehavior` was set explicitly, honor it.
        // - Otherwise auto-detect:
        //     - When the search controller is presented via `navigationItem.searchController`
        //       (i.e., we're inside a UINavigationController), use Automatic so UIKit reserves
        //       space for the navigation bar / large title and the table doesn't render under it.
        //     - When the search bar is used as `tableHeaderView` (no enclosing nav controller),
        //       use Never so the header view doesn't double-inset.
        const explicit = this.iosSearchInsetBehavior;
        const usingNavItem = !!(viewController && SDK_VERSION >= 11.0 && viewController.navigationItem && viewController.navigationItem.searchController === this._searchController);
        const resolved = explicit ?? (usingNavItem ? 'automatic' : 'never');
        this._applyContentInsetBehavior(resolved);
        if (Trace.isEnabled()) {
            Trace.write(`ListView: UISearchController setup complete with searchAutoHide: ${this.searchAutoHide}, insetBehavior: ${resolved}`, Trace.categories.Debug);
        }
    }
    _applyContentInsetBehavior(value) {
        const nativeView = this.nativeViewProtected;
        if (!nativeView) {
            return;
        }
        if (nativeView.respondsToSelector('setContentInsetAdjustmentBehavior:')) {
            let mapped;
            switch (value) {
                case 'scrollableAxes':
                    mapped = 1 /* UIScrollViewContentInsetAdjustmentBehavior.ScrollableAxes */;
                    break;
                case 'never':
                    mapped = 2 /* UIScrollViewContentInsetAdjustmentBehavior.Never */;
                    break;
                case 'always':
                    mapped = 3 /* UIScrollViewContentInsetAdjustmentBehavior.Always */;
                    break;
                case 'automatic':
                default:
                    mapped = 0 /* UIScrollViewContentInsetAdjustmentBehavior.Automatic */;
            }
            nativeView.contentInsetAdjustmentBehavior = mapped;
        }
        else {
            // iOS 10 and below
            nativeView.automaticallyAdjustsScrollIndicatorInsets = value === 'automatic' || value === 'always';
        }
    }
    _cleanupSearchController() {
        if (!this._searchController) {
            return;
        }
        // Remove search controller from navigation item or table header
        const viewController = this._getViewController();
        if (viewController && viewController.navigationItem && viewController.navigationItem.searchController === this._searchController) {
            viewController.navigationItem.searchController = null;
        }
        else if (this.nativeViewProtected.tableHeaderView === this._searchController.searchBar) {
            this.nativeViewProtected.tableHeaderView = null;
        }
        // Reset content inset adjustment behavior
        if (this.nativeViewProtected.respondsToSelector('setContentInsetAdjustmentBehavior:')) {
            // iOS 11+ - restore automatic content inset adjustments
            this.nativeViewProtected.contentInsetAdjustmentBehavior = 0 /* UIScrollViewContentInsetAdjustmentBehavior.Automatic */;
        }
        else {
            // iOS 10 and below - restore automatic content inset
            this.nativeViewProtected.automaticallyAdjustsScrollIndicatorInsets = true;
        }
        // Cleanup references
        this._searchController.searchResultsUpdater = null;
        this._searchController = null;
        this._searchDelegate = null;
    }
    _getViewController() {
        // Helper to get the current view controller
        let parent = this.parent;
        while (parent) {
            if (parent.viewController) {
                return parent.viewController;
            }
            parent = parent.parent;
        }
        return null;
    }
    _setNativeClipToBounds() {
        // Always set clipsToBounds for list-view
        const view = this.nativeViewProtected;
        if (view) {
            view.clipsToBounds = true;
        }
    }
    onLoaded() {
        super.onLoaded();
        if (this._isDataDirty) {
            this.refresh();
        }
        this.nativeViewProtected.delegate = this._delegate;
        // Setup search controller if enabled
        if (this.showSearch) {
            this._setupSearchController();
        }
    }
    // @ts-ignore
    get ios() {
        return this.nativeViewProtected;
    }
    get _childrenCount() {
        return this._map.size + this._headerMap.size;
    }
    eachChildView(callback) {
        this._map.forEach((view, key) => {
            callback(view);
        });
        this._headerMap.forEach((view, key) => {
            callback(view);
        });
    }
    scrollToIndex(index) {
        this._scrollToIndex(index, false);
    }
    scrollToIndexAnimated(index) {
        this._scrollToIndex(index);
    }
    _scrollToIndex(index, animated = true) {
        if (!this.nativeViewProtected) {
            return;
        }
        const itemsLength = this.items ? this.items.length : 0;
        // mimic Android behavior that silently coerces index values within [0, itemsLength - 1] range
        if (itemsLength > 0) {
            if (index < 0) {
                index = 0;
            }
            else if (index >= itemsLength) {
                index = itemsLength - 1;
            }
            this.nativeViewProtected.scrollToRowAtIndexPathAtScrollPositionAnimated(NSIndexPath.indexPathForItemInSection(index, 0), 1 /* UITableViewScrollPosition.Top */, animated);
        }
        else if (Trace.isEnabled()) {
            Trace.write(`Cannot scroll listview to index ${index} when listview items not set`, Trace.categories.Binding);
        }
    }
    refresh() {
        // clear bindingContext when it is not observable because otherwise bindings to items won't reevaluate
        this._map.forEach((view, nativeView, map) => {
            if (!(view.bindingContext instanceof Observable)) {
                view.bindingContext = null;
            }
        });
        this._headerMap.forEach((view, nativeView, map) => {
            if (!(view.bindingContext instanceof Observable)) {
                view.bindingContext = null;
            }
        });
        if (this.isLoaded) {
            this.nativeViewProtected.reloadData();
            this.requestLayout();
            this._isDataDirty = false;
        }
        else {
            this._isDataDirty = true;
        }
    }
    isItemAtIndexVisible(itemIndex) {
        const indexes = Array.from(this.nativeViewProtected.indexPathsForVisibleRows);
        return indexes.some((visIndex) => visIndex.row === itemIndex);
    }
    getHeight(index, section = 0) {
        return this._heights[section]?.[index];
    }
    setHeight(index, value, section = 0) {
        if (!this._heights[section]) {
            this._heights[section] = new Array();
        }
        this._heights[section][index] = value;
    }
    _onRowHeightPropertyChanged(oldValue, newValue) {
        const value = layout.toDeviceIndependentPixels(this._effectiveRowHeight);
        const nativeView = this.nativeViewProtected;
        if (value < 0) {
            nativeView.rowHeight = UITableViewAutomaticDimension;
            nativeView.estimatedRowHeight = DEFAULT_HEIGHT;
            this._delegate = UITableViewDelegateImpl.initWithOwner(new WeakRef(this));
        }
        else {
            nativeView.rowHeight = value;
            nativeView.estimatedRowHeight = value;
            this._delegate = UITableViewRowHeightDelegateImpl.initWithOwner(new WeakRef(this));
        }
        if (this.isLoaded) {
            nativeView.delegate = this._delegate;
        }
        super._onRowHeightPropertyChanged(oldValue, newValue);
    }
    requestLayout() {
        // When preparing cell or header don't call super - no need to invalidate our measure when cell/header desiredSize is changed.
        if (!this._preparingCell && !this._preparingHeader) {
            super.requestLayout();
        }
    }
    measure(widthMeasureSpec, heightMeasureSpec) {
        const changed = this._currentWidthMeasureSpec !== widthMeasureSpec || this._currentHeightMeasureSpec !== heightMeasureSpec;
        this.widthMeasureSpec = widthMeasureSpec;
        super.measure(widthMeasureSpec, heightMeasureSpec);
        // Reload native view cells only in the case of size change
        if (changed) {
            this.nativeViewProtected.reloadData();
        }
    }
    onMeasure(widthMeasureSpec, heightMeasureSpec) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec);
        this._map.forEach((childView, listViewCell) => {
            View.measureChild(this, childView, childView._currentWidthMeasureSpec, childView._currentHeightMeasureSpec);
        });
        this._headerMap.forEach((childView, listViewHeaderCell) => {
            View.measureChild(this, childView, childView._currentWidthMeasureSpec, childView._currentHeightMeasureSpec);
        });
    }
    onLayout(left, top, right, bottom) {
        super.onLayout(left, top, right, bottom);
        this._map.forEach((childView, listViewCell) => {
            const rowHeight = this._effectiveRowHeight;
            const cellHeight = rowHeight > 0 ? rowHeight : this.getHeight(childView._listViewItemIndex, childView._listViewSectionIndex ?? 0);
            if (cellHeight) {
                const width = layout.getMeasureSpecSize(this.widthMeasureSpec);
                childView.iosOverflowSafeAreaEnabled = false;
                View.layoutChild(this, childView, 0, 0, width, cellHeight);
            }
        });
        this._headerMap.forEach((childView, listViewHeaderCell) => {
            const headerHeight = this.stickyHeaderHeight === 'auto' ? 44 : Length.toDevicePixels(this.stickyHeaderHeight, 44);
            const width = layout.getMeasureSpecSize(this.widthMeasureSpec);
            childView.iosOverflowSafeAreaEnabled = false;
            View.layoutChild(this, childView, 0, 0, width, headerHeight);
        });
    }
    _layoutCell(cellView, indexPath) {
        if (cellView) {
            const rowHeight = this._effectiveRowHeight;
            const heightMeasureSpec = rowHeight >= 0 ? layout.makeMeasureSpec(rowHeight, layout.EXACTLY) : infinity;
            const measuredSize = View.measureChild(this, cellView, this.widthMeasureSpec, heightMeasureSpec);
            const height = measuredSize.measuredHeight;
            this.setHeight(indexPath.row, height, indexPath.section);
            return height;
        }
        return this.nativeViewProtected.estimatedRowHeight;
    }
    _prepareCell(cell, indexPath) {
        let cellHeight;
        try {
            this._preparingCell = true;
            let view = cell.view;
            if (!view) {
                if (this.sectioned) {
                    view = this._getItemTemplateInSection(indexPath.section, indexPath.row).createView();
                }
                else {
                    view = this._getItemTemplate(indexPath.row).createView();
                }
            }
            const args = notifyForItemAtIndex(this, cell, view, ITEMLOADING, indexPath);
            view = args.view || this._getDefaultItemContent(this.sectioned ? indexPath.row : indexPath.row);
            // Proxy containers should not get treated as layouts.
            // Wrap them in a real layout as well.
            if (view instanceof ProxyViewContainer) {
                const sp = new StackLayout();
                sp.addChild(view);
                view = sp;
            }
            // If cell is reused it have old content - remove it first.
            if (!cell.view) {
                cell.owner = new WeakRef(view);
            }
            else if (cell.view !== view) {
                // Remove view from super view now as nativeViewProtected will be null afterwards
                cell.view.nativeViewProtected?.removeFromSuperview();
                this._removeContainer(cell);
                cell.owner = new WeakRef(view);
            }
            if (this.sectioned) {
                this._prepareItemInSection(view, indexPath.section, indexPath.row);
                view._listViewItemIndex = indexPath.row; // Keep row index for compatibility
                view._listViewSectionIndex = indexPath.section;
            }
            else {
                this._prepareItem(view, indexPath.row);
                view._listViewItemIndex = indexPath.row;
            }
            this._map.set(cell, view);
            // We expect that views returned from itemLoading are new (e.g. not reused).
            if (view && !view.parent) {
                this._addView(view);
                cell.contentView.addSubview(view.nativeViewProtected);
            }
            cellHeight = this._layoutCell(view, indexPath);
        }
        finally {
            this._preparingCell = false;
        }
        return cellHeight;
    }
    _removeContainer(cell) {
        const view = cell.view;
        // This is to clear the StackLayout that is used to wrap ProxyViewContainer instances.
        if (!(view.parent instanceof ListView)) {
            this._removeView(view.parent);
        }
        // No need to request layout when we are removing cells.
        const preparing = this._preparingCell;
        this._preparingCell = true;
        view.parent._removeView(view);
        view._listViewItemIndex = undefined;
        view._listViewSectionIndex = undefined;
        this._preparingCell = preparing;
        this._map.delete(cell);
    }
    _prepareHeader(headerCell, section) {
        let headerHeight;
        try {
            this._preparingHeader = true;
            let view = headerCell.view;
            if (!view) {
                view = this._getHeaderTemplate();
                if (!view) {
                    if (Trace.isEnabled()) {
                        Trace.write(`ListView: Failed to create header view for section ${section}`, Trace.categories.Debug);
                    }
                    // Create a fallback view
                    const lbl = new Label();
                    lbl.text = `Section ${section}`;
                    view = lbl;
                }
            }
            // Handle header cell reuse
            if (!headerCell.view) {
                headerCell.owner = new WeakRef(view);
            }
            else if (headerCell.view !== view) {
                // Remove old view and set new one
                headerCell.view.nativeViewProtected?.removeFromSuperview();
                this._removeHeaderContainer(headerCell);
                headerCell.owner = new WeakRef(view);
            }
            // Clear existing binding context and set new one
            if (view.bindingContext) {
                view.bindingContext = null;
            }
            if (this.sectioned) {
                const sectionData = this._getSectionData(section);
                if (sectionData) {
                    view.bindingContext = sectionData;
                }
                else {
                    // Fallback if section data is missing
                    view.bindingContext = { title: `Section ${section}`, section: section };
                }
            }
            else {
                view.bindingContext = this.bindingContext;
            }
            // Force immediate binding context evaluation
            if (view && typeof view._onBindingContextChanged === 'function') {
                view._onBindingContextChanged(null, view.bindingContext);
                // Also trigger for child views
                // @ts-ignore
                if (view._childrenCount) {
                    view.eachChildView((child) => {
                        if (typeof child._onBindingContextChanged === 'function') {
                            child._onBindingContextChanged(null, view.bindingContext);
                        }
                        return true;
                    });
                }
            }
            this._headerMap.set(headerCell, view);
            // Add new header view to the cell
            if (view && !view.parent) {
                this._addView(view);
                headerCell.contentView.addSubview(view.nativeViewProtected);
            }
            // Request layout and measure/layout the header
            if (view && view.bindingContext) {
                view.requestLayout();
            }
            headerHeight = this._layoutHeader(view);
        }
        finally {
            this._preparingHeader = false;
        }
        return headerHeight;
    }
    _layoutHeader(headerView) {
        if (headerView) {
            const headerHeight = this.stickyHeaderHeight === 'auto' ? 44 : Length.toDevicePixels(this.stickyHeaderHeight, 44);
            const heightMeasureSpec = layout.makeMeasureSpec(headerHeight, layout.EXACTLY);
            const measuredSize = View.measureChild(this, headerView, this.widthMeasureSpec, heightMeasureSpec);
            // Layout the header with the measured size
            View.layoutChild(this, headerView, 0, 0, measuredSize.measuredWidth, measuredSize.measuredHeight);
            return measuredSize.measuredHeight;
        }
        return 44;
    }
    _getHeaderTemplate() {
        if (this.stickyHeaderTemplate) {
            if (__UI_USE_EXTERNAL_RENDERER__) {
                if (isFunction(this.stickyHeaderTemplate)) {
                    return this.stickyHeaderTemplate();
                }
            }
            else {
                if (typeof this.stickyHeaderTemplate === 'string') {
                    try {
                        const parsed = Builder.parse(this.stickyHeaderTemplate, this);
                        if (!parsed) {
                            // Create a simple fallback
                            const fallbackLabel = new Label();
                            fallbackLabel.text = 'Parse Failed';
                            return fallbackLabel;
                        }
                        return parsed;
                    }
                    catch (error) {
                        if (Trace.isEnabled()) {
                            Trace.write(`ListView: Template parsing error: ${error}`, Trace.categories.Debug);
                        }
                        // Create a simple fallback
                        const errorLabel = new Label();
                        errorLabel.text = 'Template Error';
                        return errorLabel;
                    }
                }
                else {
                    const view = this.stickyHeaderTemplate();
                    if (Trace.isEnabled()) {
                        Trace.write(`ListView: Created header view from template function: ${!!view} (type: ${view?.constructor?.name})`, Trace.categories.Debug);
                    }
                    return view;
                }
            }
        }
        if (Trace.isEnabled()) {
            Trace.write(`ListView: No sticky header template, creating default`, Trace.categories.Debug);
        }
        // Return a default header if no template is provided
        const lbl = new Label();
        lbl.text = 'Default Header';
        return lbl;
    }
    _removeHeaderContainer(headerCell) {
        const view = headerCell.view;
        // This is to clear the StackLayout that is used to wrap ProxyViewContainer instances.
        if (!(view.parent instanceof ListView)) {
            this._removeView(view.parent);
        }
        // No need to request layout when we are removing headers.
        const preparing = this._preparingHeader;
        this._preparingHeader = true;
        view.parent._removeView(view);
        this._preparingHeader = preparing;
        this._headerMap.delete(headerCell);
    }
    [separatorColorProperty.getDefault]() {
        return this.nativeViewProtected.separatorColor;
    }
    [separatorColorProperty.setNative](value) {
        this.nativeViewProtected.separatorColor = value instanceof Color ? value.ios : value;
    }
    [itemTemplatesProperty.getDefault]() {
        return null;
    }
    [itemTemplatesProperty.setNative](value) {
        this._itemTemplatesInternal = new Array(this._defaultTemplate);
        if (value) {
            for (let i = 0, length = value.length; i < length; i++) {
                this.nativeViewProtected.registerClassForCellReuseIdentifier(ListViewCell.class(), value[i].key);
            }
            this._itemTemplatesInternal = this._itemTemplatesInternal.concat(value);
        }
        this.refresh();
    }
    [iosEstimatedRowHeightProperty.getDefault]() {
        return DEFAULT_HEIGHT;
    }
    [iosEstimatedRowHeightProperty.setNative](value) {
        const nativeView = this.nativeViewProtected;
        const estimatedHeight = layout.toDeviceIndependentPixels(Length.toDevicePixels(value, 0));
        nativeView.estimatedRowHeight = estimatedHeight < 0 ? DEFAULT_HEIGHT : estimatedHeight;
    }
    [stickyHeaderProperty.getDefault]() {
        return false;
    }
    [stickyHeaderProperty.setNative](value) {
        if (Trace.isEnabled()) {
            Trace.write(`ListView: stickyHeader set to ${value}`, Trace.categories.Debug);
        }
        // Immediately refresh to apply changes
        if (this.isLoaded) {
            this.refresh();
        }
    }
    [stickyHeaderTemplateProperty.getDefault]() {
        return null;
    }
    [stickyHeaderTemplateProperty.setNative](value) {
        if (Trace.isEnabled()) {
            Trace.write(`ListView: stickyHeaderTemplate set: ${typeof value} ${value ? '(has value)' : '(null)'}`, Trace.categories.Debug);
        }
        // Clear any cached template
        this._headerTemplateCache = null;
        // Immediately refresh to apply changes
        if (this.isLoaded) {
            this.refresh();
        }
    }
    [stickyHeaderHeightProperty.getDefault]() {
        return 'auto';
    }
    [stickyHeaderHeightProperty.setNative](value) {
        if (Trace.isEnabled()) {
            Trace.write(`ListView: stickyHeaderHeight set to ${value}`, Trace.categories.Debug);
        }
        // Immediately refresh to apply changes
        if (this.isLoaded) {
            this.refresh();
        }
    }
    [sectionedProperty.getDefault]() {
        return false;
    }
    [sectionedProperty.setNative](value) {
        if (Trace.isEnabled()) {
            Trace.write(`ListView: sectioned set to ${value}`, Trace.categories.Debug);
        }
        // Immediately refresh to apply changes
        if (this.isLoaded) {
            this.refresh();
        }
    }
    [showSearchProperty.getDefault]() {
        return false;
    }
    [showSearchProperty.setNative](value) {
        if (Trace.isEnabled()) {
            Trace.write(`ListView: showSearch set to ${value}`, Trace.categories.Debug);
        }
        if (value) {
            this._setupSearchController();
        }
        else {
            this._cleanupSearchController();
        }
    }
    [iosSearchInsetBehaviorProperty.setNative](value) {
        // Only apply live if the search controller is already set up. If not, the value
        // will be picked up by _setupSearchController() when it runs.
        if (this.showSearch && this._searchController) {
            this._applyContentInsetBehavior(value);
        }
    }
    [searchAutoHideProperty.getDefault]() {
        return false;
    }
    [searchAutoHideProperty.setNative](value) {
        if (Trace.isEnabled()) {
            Trace.write(`ListView: searchAutoHide set to ${value}`, Trace.categories.Debug);
        }
        // If search is already enabled, update the existing search controller
        if (this.showSearch && this._searchController) {
            const viewController = this._getViewController();
            if (viewController && viewController.navigationItem && SDK_VERSION >= 11.0) {
                viewController.navigationItem.hidesSearchBarWhenScrolling = value;
                // Enable large titles for better auto-hide effect when searchAutoHide is true
                // if (value && viewController.navigationController && viewController.navigationController.navigationBar) {
                // 	if (!viewController.navigationController.navigationBar.prefersLargeTitles) {
                // 		viewController.navigationController.navigationBar.prefersLargeTitles = true;
                // 	}
                // 	if (viewController.navigationItem.largeTitleDisplayMode === UINavigationItemLargeTitleDisplayMode.Automatic) {
                // 		viewController.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayMode.Always;
                // 	}
                // }
            }
        }
        // If search is not enabled yet, the property will be used when _setupSearchController is called
    }
}
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], ListView.prototype, "onLoaded", null);
//# sourceMappingURL=index.ios.js.map