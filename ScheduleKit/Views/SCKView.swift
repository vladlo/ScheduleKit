/*
 *  SCKView.swift
 *  ScheduleKit
 *
 *  Created:    Guillem Servera on 24/12/2014.
 *  Copyright:  © 2014-2016 Guillem Servera (http://github.com/gservera)
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to deal
 *  in the Software without restriction, including without limitation the rights
 *  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 *  copies of the Software, and to permit persons to whom the Software is
 *  furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 *  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 *  THE SOFTWARE.
 */

import Cocoa

/// An object conforming to the `SCKViewDelegate` protocol must implement a
/// method required to set a color schedule view events.
@objc public protocol SCKViewDelegate {
    @objc (colorForEventKind:inScheduleView:)
    optional func color(for eventKindValue: Int, in scheduleView: SCKView) -> NSColor
}



/// An abstract NSView subclass that implements the basic functionality to manage
/// a set of event views provided by an `SCKViewController` object. This class
/// provides basic handling of the displayed date interval and methods to convert
/// between these date values and view coordinates.
///
/// In addition, `SCKView` provides the default (and required) implementation for
/// event coloring, selection and deselection, handling double clicks on empty
/// dates and drag & drop.

@objc public class SCKView: NSView {
    
    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }
    
    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }
    
    /// This method is intended to provide a common initialization point for all 
    /// instances, regardless of whether they have been initialized using
    /// `init(frame:)` or `init(coder:)`. Default implementation does nothing.
    func setUp() { }
    
    
    // MARK: - Date handling
    
    public var dateInterval: DateInterval = DateInterval() {
        didSet { needsDisplay = true }
    }
    
    /// The lowest displayed date.
    public private(set) var startDate: Date = Date() {
        didSet { absoluteStartTimeRef = startDate.timeIntervalSinceReferenceDate }
    }
    
    /// The highest display date.
    public private(set) var endDate: Date = Date() {
        didSet { absoluteEndTimeRef = endDate.timeIntervalSinceReferenceDate }
    }
    
    /// The lowest displayed date as a time interval since reference date.
    private(set) var absoluteStartTimeRef: Double = 0.0
    
    /// The highest displayed date as a time interval since reference date.
    private(set) var absoluteEndTimeRef: Double = 0.0
    
    /// The total number of seconds displayed.
    var absoluteTimeInterval: TimeInterval {
        return absoluteEndTimeRef - absoluteStartTimeRef
    }
    
    //Must call reloadData after
    @objc public func setDateBounds(lower sD: Date, upper eD: Date) {
        startDate = sD
        endDate = eD
        needsDisplay = true
    }
    
    // MARK: -
    
    /// The schedule view's delegate.
    public weak var delegate: SCKViewDelegate?
    

    
    
    
    /** The style used by subviews to draw their background. @see ScheduleKitDefinitions.h */
    @objc public var colorMode: SCKEventColorMode = .byEventKind {
        didSet {
            if colorMode != oldValue {
                for eventView in eventViews {
                    eventView.backgroundColor = nil
                    eventView.needsDisplay = true
                }
            }
        }
    }
    
    weak var selectedEventView: SCKEventView? {
        willSet {
            if selectedEventView != nil && newValue == nil {
                controller.eventManager?.scheduleControllerDidClearSelection(controller)
            }
        }
        didSet {
            for eventView in eventViews {
                eventView.needsDisplay = true
            }
            if selectedEventView != nil {
                controller.eventManager?.scheduleController(controller, didSelectEvent: selectedEventView!.eventHolder.representedObject)
            }
        }
    }
    
    @IBOutlet public weak var controller: SCKViewController!
    /** This property is set to YES when a relayout has been triggered and back to NO when the
     process finishes. Mind that relayout methods are invoked quite often. */
    private(set) var isRelayoutInProgress: Bool = false
    
    
    /**< SCKEventView subviews */
    private var eventViews: [SCKEventView] = []
    /**< When dragging, the subview being dragged */
    internal weak var eventViewBeingDragged: SCKEventView?
    
    
    
    //FIXME: Notification observer
    
    public override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        NSRectFill(dirtyRect)
    }
    

    public override func mouseDown(with event: NSEvent) {
        // Called when user clicks on an empty space.
        // Deselect selected event view if any
        selectedEventView = nil
        // If double clicked on valid coordinates, notify the event manager's delegate.
        if event.clickCount == 2 {
            let loc = convert(event.locationInWindow, from: nil)
            let offset = relativeTimeLocation(for: loc)
            if offset != Double(NSNotFound) {
                let blankDate = calculateDate(for: offset)!
                controller.eventManager?.scheduleController(controller, didDoubleClickBlankDate: blankDate)
            }
        }
    }

    
    public override var isFlipped: Bool { return true }
    public override var isOpaque: Bool { return true }
    
    
    var contentRect: CGRect {
        return CGRect(origin: .zero, size: frame.size)
    }
    
    
    
    
    
    /**
     *  Calculates the date represented by a specific relative time location between @c
     *  startDate and @c endDate. Note that seconds are rounded so they'll be zero.
     *  @param offset The relative time location. Should be a value between 0.0 and 1.0.
     *  @return The calculated NSDate object or nil if @c offset is not valid.
     */
    func calculateDate(for relativeTimeLocation: Double) -> Date? {
        guard relativeTimeLocation >= 0.0 && relativeTimeLocation <= 1.0 else {
            return nil
        }
        var numberOfSeconds = Int(trunc(absoluteStartTimeRef + relativeTimeLocation * absoluteTimeInterval))
        // Round to next minute
        while numberOfSeconds % 60 > 0 {
            numberOfSeconds += 1
        }
        return Date(timeIntervalSinceReferenceDate: TimeInterval(numberOfSeconds))
    
    }
    
    
    /**
     *  Calculates the relative time location between @c startDate and @c endDate for a given
     *  NSDate object.
     *
     *  @param date The date from which to perform the calculation. Should not be nil.
     *  @return A double value between 0.0 and 1.0 representing the relative position of @c
     *  date between @c startDate and @c endDate; or @c SCKRelativeTimeLocationNotFound if @c
     *  date is before @c startDate or after @c endDate.
     */
    func calculateRelativeTimeLocation(for date: Date) -> Double {
        let timeRef = date.timeIntervalSinceReferenceDate
        guard timeRef >= absoluteStartTimeRef && timeRef <= absoluteEndTimeRef else {
            return SCKRelativeTimeLocationInvalid
        }
        return (timeRef - absoluteStartTimeRef) / absoluteTimeInterval
    }
    
    /**
     *  Calculates the relative time location between @c startDate and @c for a given point
     *  inside the view coordinates. Default implementation always returns
     *  SCKRelativeLocationNotFound, consider overriding this method in subclasses.
     *
     *  @param location The NSPoint for which to perform the calculation.
     *  @return In subclasses, a double value between 0.0 and 1.0 representing the relative
     *  position of @c location between @c startDate and @c endDate; or @c
     *  SCKRelativeTimeLocationNotFound if @c location falls out of the content rect.
     */
    func relativeTimeLocation(for point: CGPoint) -> Double {
        return SCKRelativeTimeLocationInvalid
    }
    
    
    //MARK: - Subview management
    
    /**
     *  Adds an SCKEventView to the array of subviews managed by this
     *  instance. This method is typically called from the event manager.
     *  @param eventView The view to be added. Must already be a subview of self.
     */
    internal func addEventView(_ eventView: SCKEventView) {
        eventViews.append(eventView)
    }
    
    /**
     *  Removes an SCKEventView from the array of subviews managed by
     *  this instance. This method is typically called from the event manager.
     *  @param eventView The view to be removed.
     *  @discussion @c -removeFromSuperview should also be called on @c eventView.
     */
    
    internal func removeEventView(_ eventView: SCKEventView) {
        eventViews.remove(at: eventViews.index(of: eventView)!)
    }
    
    //MARK: - Drag & drop support
    
    /**
     *  Called from an @c SCKEventView subview when a drag action begins.
     *  This method sets @c _eventViewBeingDragged and @c _otherEventViews,
     *  and also calls @c -lock on the event view's event holder.
     *  @discussion Locking and unlocking for SCKEventView subviews being dragged are
     *  handled here (and not during successive relayout processes) in order to avoid
     *  inconsistencies between the drag & drop action and changes that could be
     *  observed while the @c SCKEventView is being dragged.
     *  @param eV The @c SCKEventView being dragged.
     */
    internal func beginDraggingEventView(_ eventView: SCKEventView) {
        var subviews = eventViews
        subviews.remove(at: subviews.index(of: eventView)!)
        eventViewBeingDragged = eventView
        eventView.eventHolder.freeze()
    }
    
    /**
     *  Called from an @c SCKEventView subview when a drag action moves.
     *  This method sets this view as needing display (to make dragging guides appear)
     *  and triggers a relayout for other event views (since conflicts may have changed).
     *  @param eV The @c SCKEventView being dragged.
     */
    internal func continueDraggingEventView(_ eventView: SCKEventView) {
        invalidateFrames(for: eventViews)
        layoutSubtreeIfNeeded()
        needsDisplay = true
    }
    
    /**
     *  Called from an @c SCKEventView subview when a drag action ends.
     *  This method clears @c _eventViewBeingDragged and @c _otherEventViews,
     *  calls @c -unlock on the event view's event holder, triggers a final relayout
     *  and finally sets this view as needing display (to clear dragging guides).
     *  @discussion Locking and unlocking for SCKEventView subviews being dragged are
     *  handled here (and not during successive relayout processes) in order to avoid
     *  inconsistencies between the drag & drop action and changes that could be
     *  observed while the @c SCKEventView is being dragged.
     *  @param eV The @c SCKEventView being dragged.
     */
    internal func endDraggingEventView(_ eventView: SCKEventView) {
        //FIXME: Needed eventViewBeingDragged having this param?
        guard let dragged = eventViewBeingDragged else {
            return
        }
        dragged.eventHolder.unfreeze()
        eventViewBeingDragged = nil
        invalidateFrameForAllEventViews()
        needsDisplay = true
    }
    
    //MARK: - Event view layout
    
    /**
     *  This method is called when a relayout is triggered. You may override it to
     *  perform additional tasks before the actual relayout process takes place. In
     *  that case, you must call super.
     */
    private func beginRelayout() {
        isRelayoutInProgress = true
    }
    
    /**
     *  SCKView subclasses override this method to implement positioning (updating
     *  frame) of their SCKEventView subviews when a relayout process is triggered.
     *  The ultimate objective of this method is to calculate a new frame for a
     *  concrete subview based on the properties of its holder. Conflict calculations
     *  should also be performed here. Default implementation does nothing.
     *
     *  @param eventView The event view whose frame needs to be updated.
     *  @param animation YES if change should be animated, NO instead.
     */
    func invalidateFrame(for eventView: SCKEventView) {
        // Default implementation does nothing
        needsLayout = true
    }
    
    /**
     *  This methods performs a series of operations in order to relayout an array of
     *  SCKEventView objects according to their date, duration and other events in conflict.
     *  The full process implies locking all subviews' event holder (as to prevent changes
     *  on their properties while conflict calculations take place), calling
     *  @c relayoutEventView:animated: for each SCKEventView in @c eventViews and finally
     *  unlocking the previously locked event holders.
     *
     *  @discussion When an event view is being dragged, its event holder does not get locked
     *  or unlocked.
     *  @discussion Don't override this method. See @c beginRelayout and @c endRelayout instead.
     *
     *  @param eventViews The array of SCKEventView objects to be redrawn.
     *  @param animation  Pass YES if you want relayout to have animation. Pass no instead.
     */
    func invalidateFrames(for eventViews: [SCKEventView]) {
        guard !isRelayoutInProgress else {
            Swift.print("Warning: Invalidation already triggered")
            return
        }
        var allHolders = controller.eventHolders
        if eventViewBeingDragged != nil {
            let idx = allHolders.index(where: { (tested) -> Bool in
                return (tested === eventViewBeingDragged!.eventHolder!)
            })!
            allHolders.remove(at: idx)
        }
        
        beginRelayout()
        
        for holder in allHolders {
            holder.freeze()
        }
        
        //TODO: Combine animations
        for eventView in eventViews {
            invalidateFrame(for: eventView)
        }
        
        for holder in allHolders {
            holder.unfreeze()
        }
        
        endRelayout()
    }
    
    /**
     *  Calls @c triggerRelayoutForEventViews:animated: passing all event views and NO as
     *  parameters.
     */
    func invalidateFrameForAllEventViews() {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current().duration = 1.0
        invalidateFrames(for: eventViews)
        animator().layoutSubtreeIfNeeded()
        NSAnimationContext.endGrouping()
    }
    
    /**
     *  This method is called when a relayout finishes. You may override it to
     *  perform additional tasks after the actual relayout process takes place. In
     *  that case, you must call super.
     */
    func endRelayout() {
        isRelayoutInProgress = false
    }
    
}
