// SPDX-FileCopyrightText: 2019-2023 Connor McLaughlin <stenzek@gmail.com>
// SPDX-License-Identifier: (GPL-3.0 OR CC-BY-NC-ND-4.0)

#include "cocoa_progress_callback.h"

#include "common/log.h"

Log_SetChannel(CocoaProgressCallback);

CocoaProgressCallback::CocoaProgressCallback() : BaseProgressCallback()
{
  Create();
}

CocoaProgressCallback::~CocoaProgressCallback()
{
  Destroy();
}

void CocoaProgressCallback::PushState()
{
  BaseProgressCallback::PushState();
}

void CocoaProgressCallback::PopState()
{
  BaseProgressCallback::PopState();
  UpdateProgress();
}

void CocoaProgressCallback::SetCancellable(bool cancellable)
{
  BaseProgressCallback::SetCancellable(cancellable);
}

void CocoaProgressCallback::SetTitle(const char* title)
{
  dispatch_async(dispatch_get_main_queue(), [this, title = [[NSString alloc] initWithUTF8String:title]]() {
    [m_window setTitle:title];
    [title release];
  });
}

void CocoaProgressCallback::SetStatusText(const char* text)
{
  BaseProgressCallback::SetStatusText(text);
  dispatch_async(dispatch_get_main_queue(), [this, title = [[NSString alloc] initWithUTF8String:text]]() {
    [m_status setStringValue:title];
    [title release];
  });
}

void CocoaProgressCallback::SetProgressRange(u32 range)
{
  BaseProgressCallback::SetProgressRange(range);
  UpdateProgress();
}

void CocoaProgressCallback::SetProgressValue(u32 value)
{
  BaseProgressCallback::SetProgressValue(value);
  UpdateProgress();
}

bool CocoaProgressCallback::Create()
{
  @autoreleasepool
  {
    const NSRect window_rect =
      NSMakeRect(0.0f, 0.0f, static_cast<float>(WINDOW_WIDTH), static_cast<float>(WINDOW_HEIGHT));
    constexpr NSWindowStyleMask style = NSWindowStyleMaskTitled;
    m_window = [[NSWindow alloc] initWithContentRect:window_rect
                                           styleMask:style
                                             backing:NSBackingStoreBuffered
                                               defer:NO];

    NSView* m_view;
    m_view = [[NSView alloc] init];
    [m_window setContentView:m_view];

    int x = WINDOW_MARGIN;
    int y = WINDOW_HEIGHT - WINDOW_MARGIN;

    y -= 16 + SUBWINDOW_PADDING;
    m_status = [NSTextField labelWithString:@"Initializing..."];
    [m_status setFrame:NSMakeRect(x, y, SUBWINDOW_WIDTH, 16)];
    [m_view addSubview:m_status];

    y -= 16 + SUBWINDOW_PADDING;
    m_progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(x, y, SUBWINDOW_WIDTH, 16)];
    [m_progress setMinValue:0];
    [m_progress setMaxValue:100];
    [m_progress setDoubleValue:0];
    [m_progress setIndeterminate:NO];
    [m_view addSubview:m_progress];

    y -= 170 + SUBWINDOW_PADDING;
    m_text_scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(x, y, SUBWINDOW_WIDTH, 170)];
    [m_text_scroll setBorderType:NSBezelBorder];
    [m_text_scroll setHasVerticalScroller:YES];
    [m_text_scroll setHasHorizontalScroller:NO];

    const NSSize content_size = [m_text_scroll contentSize];
    m_text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, content_size.width, content_size.height)];
    [m_text setMinSize:NSMakeSize(0, content_size.height)];
    [m_text setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    [m_text setVerticallyResizable:YES];
    [m_text setHorizontallyResizable:NO];
    [m_text setAutoresizingMask:NSViewWidthSizable];
    [m_text setUsesAdaptiveColorMappingForDarkAppearance:YES];
    [[m_text textContainer] setContainerSize:NSMakeSize(content_size.width, FLT_MAX)];
    [[m_text textContainer] setWidthTracksTextView:YES];
    [m_text_scroll setDocumentView:m_text];
    [m_view addSubview:m_text_scroll];

    [m_window center];
    [m_window setIsVisible:TRUE];
    [m_window makeKeyAndOrderFront:nil];
    [m_window setReleasedWhenClosed:NO];
  }

  return true;
}

void CocoaProgressCallback::Destroy()
{
  if (m_window == nil)
    return;

  [m_window close];

  m_text = nil;
  m_progress = nil;
  m_status = nil;

  [m_view release];
  m_view = nil;

  [m_window release];
  m_window = nil;
}

void CocoaProgressCallback::UpdateProgress()
{
  const float percent = (static_cast<float>(m_progress_value) / static_cast<float>(m_progress_range)) * 100.0f;
  dispatch_async(dispatch_get_main_queue(), [this, percent]() {
    [m_progress setDoubleValue:percent];
  });
}

void CocoaProgressCallback::DisplayError(const char* message)
{
  Log_ErrorPrint(message);
  AppendMessage(message);
}

void CocoaProgressCallback::DisplayWarning(const char* message)
{
  Log_WarningPrint(message);
  AppendMessage(message);
}

void CocoaProgressCallback::DisplayInformation(const char* message)
{
  Log_InfoPrint(message);
  AppendMessage(message);
}

void CocoaProgressCallback::AppendMessage(const char* message)
{
  @autoreleasepool
  {
    NSString* nsmessage = [[[NSString stringWithUTF8String:message] stringByAppendingString:@"\n"] retain];
    dispatch_async(dispatch_get_main_queue(), [this, nsmessage]() {
      @autoreleasepool
      {
        NSAttributedString* attr = [[[NSAttributedString alloc] initWithString:nsmessage] autorelease];
        [[m_text textStorage] appendAttributedString:attr];
        [m_text scrollRangeToVisible:NSMakeRange([[m_text string] length], 0)];
        [nsmessage release];
      }
    });
  }
}

void CocoaProgressCallback::DisplayDebugMessage(const char* message)
{
  Log_DevPrint(message);
}

void CocoaProgressCallback::ModalError(const char* message)
{
  if (![NSThread isMainThread])
  {
    dispatch_sync(dispatch_get_main_queue(), [this, message]() { ModalError(message); });
    return;
  }

  @autoreleasepool
  {
    NSAlert* alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:[NSString stringWithUTF8String:message]];
    [alert setAlertStyle:NSAlertStyleCritical];
    [alert runModal];
  }
}

bool CocoaProgressCallback::ModalConfirmation(const char* message)
{
  if (![NSThread isMainThread])
  {
    bool result;
    dispatch_sync(dispatch_get_main_queue(), [this, message, &result]() { result = ModalConfirmation(message); });
    return result;
  }

  bool result;
  @autoreleasepool
  {
    NSAlert* alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:[NSString stringWithUTF8String:message]];
    [alert addButtonWithTitle:@"Yes"];
    [alert addButtonWithTitle:@"No"];
    result = ([alert runModal] == NSAlertFirstButtonReturn);
  }

  return result;
}

void CocoaProgressCallback::ModalInformation(const char* message)
{
  if (![NSThread isMainThread])
  {
    dispatch_sync(dispatch_get_main_queue(), [this, message]() { ModalInformation(message); });
    return;
  }

  @autoreleasepool
  {
    NSAlert* alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:[NSString stringWithUTF8String:message]];
    [alert runModal];
  }
}
