/// Creates the archetype selection step.
pub const ChooseArchetypeStep = @import("ChooseArchetypeStep.zig").ChooseArchetypeStep;
/// Creates the final character confirmation step.
pub const ConfirmCharacterStep = @import("ConfirmCharacterStep.zig").ConfirmCharacterStep;
/// Creates the character statistics allocation step.
pub const ManageStatsStep = @import("ManagePointsStep.zig").ManageStatsStep;
/// Creates the character skills allocation step.
pub const ManageSkillsStep = @import("ManagePointsStep.zig").ManageSkillsStep;
/// Creates a multi-step wizard window.
pub const WizardWindow = @import("WizardWindow.zig").WizardWindow;
