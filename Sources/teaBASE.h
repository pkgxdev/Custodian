#import <PreferencePanes/PreferencePanes.h>

@interface teaBASE : NSPreferencePane<NSTableViewDataSource, NSTableViewDelegate>

@property (weak) IBOutlet NSSwitch *sshSwitch;
@property (weak) IBOutlet NSSwitch *sshPassPhraseSwitch;
@property (weak) IBOutlet NSSwitch *gpgSignSwitch;
@property (weak) IBOutlet NSSwitch *homebrewSwitch;
@property (weak) IBOutlet NSSwitch *pkgxSwitch;
@property (weak) IBOutlet NSLevelIndicator *ratingIndicator;
@property (weak) IBOutlet NSTableView *gitExtensionsTable;
@property (weak) IBOutlet NSWindow *sshPassphraseWindow;
@property (weak) IBOutlet NSWindow *gpgPassphraseWindow;
@property (weak) IBOutlet NSTextField *sshPassphraseTextField;

- (IBAction)createSSHPrivateKey:(id)sender;
- (IBAction)createSSHPassPhrase:(id)sender;

- (IBAction)openHomebrewHome:(id)sender;
- (IBAction)openPkgxHome:(id)sender;
- (IBAction)installPkgx:(id)sender;

- (IBAction)openGitHub:(id)sender;

- (IBAction)modalCancel:(id)sender;

@end
