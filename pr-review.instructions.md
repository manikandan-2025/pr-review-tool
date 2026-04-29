---
applyTo:
  - "**/*.ts"
  - "**/*.html"
  - "**/*.spec.ts"
  - "**/*.json"
---

# Code Review Guidelines — `dedalus-cis4u/pas-ou`

This document consolidates review feedback from reviewers **meghanagaraja-1405**, **berndschneiders**, and **Ashwinidedalus** on PRs authored by **sgovindasam3**, **Ashwinidedalus**, **Geetha-P15**, **Yamini-U**, **Yoga-Dedalus**, and **manikandan-2025**.

---

## Naming Convention Rules — PR Review

| Rule | Severity | Violation |
|------|----------|-----------|
| NAME-01 | Major | Inconsistent or verbose variable/attribute names — drop redundant words (e.g., drop "preference" per team agreement; use `person-specific-info-format-valid-to`). Use full descriptive names, never abbreviations (`mc` → `medicalCase`, `c` → `catalogEntry`, `spl` → `special`) |
| NAME-02 | Minor | Boolean variable missing descriptive prefix (`is`, `has`, `can`, `should`) — e.g., `wardAttenderMode` should be `isWardAttender`, `specificInfoFormatReadOnly` should be `isSpecificFormatReadOnly` |
| NAME-03 | Minor | Route constant name is ambiguous — use descriptive names like `ROUTE_CASE_NUMBER_ADD_DEFINITION_FORM` instead of `ROUTE_CASE_NUMBER_DEFINITION_FORM` |
| NAME-04 | Major | Resource key does not reflect where data is stored or is not specific enough — e.g., use `PAS_PERSON_CASE_CERTIFICATE_ACCOUNTING_MODE` since value is persisted in the OutpatientCertificate table; rename `PAS_PATIENT_DATE_IN_FUTURE` to `PAS_PATIENT_DEATH_DATE_IN_FUTURE` |
| NAME-05 | Major | Method name does not describe its action — getters must start with `get`, validation methods with `validate`, singular for single-entity operations (`createCaseNumberDefinitions` → `createCaseNumberDefinition`) |
| NAME-06 | Major | Constants not in `ALL_CAPS` with underscores — e.g., `mockRelativeHumanBeing` should be `MOCK_RELATIVE_HUMANBEING` |
| NAME-07 | Major | Component name does not match its folder name — component name must be consistent with folder structure |
| NAME-08 | Major | String literals used where an enum should exist — create typed enums instead of raw strings (e.g., `"EDUCATION"`, `"ARMED_FORCES"` → `PersonAssociatedStatusType.EDUCATION`) |
| NAME-09 | Major | Test attributes using `data-cy` instead of `data-e2e-id` — all test attributes must use `data-e2e-id` |
| NAME-10 | Minor | Test attribute ID does not match the element's purpose — e.g., `responsibleNurse1` should be `treatmentCategory` if that is the actual control |

### NAME-01 Detail

> "Pls be consistent with naming. We decided to drop 'preference' in naming variables as it is quite long. So use `person-specific-info-format-valid-to`. Similarly other variables and attr values need renaming." — *PR #297*
>
> "pls give proper name to local variables. mc --> medicalCase, this.medicalCase -> PersonMergeMedicalCaseValueObjects, patientCases --> medicalCases" — *PR #474*

### NAME-02 Detail

```typescript
// GOOD
isWardAttender
isSpecificFormatReadOnly

// BAD
wardAttenderMode
specificInfoFormatReadOnly
```

### NAME-04 Detail

> "Change the resource key to a more relevant one — `PAS_PERSON_CASE_CERTIFICATE_ACCOUNTING_MODE`: 'Billing mode', since it is persisted in the OutpatientCertificate table." — *PR #752*
>
> "Rename 'PAS_PATIENT_DATE_IN_FUTURE' to 'PAS_PATIENT_DEATH_DATE_IN_FUTURE' for all the resource files." — *PR #599*

### NAME-05 Detail

> "Please rename createCaseNumberDefinitions to createCaseNumberDefinition" — *PR #764*
>
> "rename to getHeader()", "rename method to getLabel()" — *PR #776*

### NAME-06 Detail

> "should be in caps MOCK_RELATIVE_HUMANBEING" — *PR #590*

### NAME-07 Detail

> "component name to be same as folder name" — *PR #474*

### NAME-08 Detail

> "please create enum for AssociatedStatusType" "pls rename to 'PersonAssociatedStatusType'" — *PR #776*

### NAME-09 Detail

> "Change data-cy to data-e2e-id" — *PR #590*

### NAME-10 Detail

> "id should be renamed from responsibleNurse1 to treatmentCategory" — *PR #584*

---

## Angular Component Rules (`.component.ts`) — PR Review

| Rule | Severity | Violation |
|------|----------|-----------|
| COMP-01 | Major | Multiple nested `if` statements that can be consolidated into a single condition for readability |
| COMP-02 | Major | Missing error handling for catalog fetch methods or asynchronous operations (subscriptions, promises, HTTP calls) — `throwError` inside error callbacks is insufficient |
| COMP-03 | Minor | Redundant conditional check inside a method that is only called when the control is already visible (e.g., `if (this.isDACHL)` guard inside `onAccountingModeFocusOut()` when the method is only invoked when DACHL control is visible) |
| COMP-04 | Major | Creating a new method (e.g., `onAccountingModeFocusOut()`) when an existing method (e.g., `validateMedicalCase()`) already serves the same purpose — reuse existing methods |
| COMP-05 | Major | Initialization method (e.g., `initDACHLControls`) called more than once — must be called only at the location where the condition is determined |
| COMP-06 | Blocker | Component subscribes to observables or allocates resources but does not implement `OnDestroy` for cleanup/unsubscribe |
| COMP-07 | Major | Business logic (API calls, data fetching, complex rules) placed in component file instead of service file |
| COMP-08 | Major | Validator setup or control initialization placed in `ngOnInit` instead of constructor — validators and `isRequired` belong in constructor; data fetching and subscriptions belong in `ngOnInit` |
| COMP-09 | Major | Duplicate validator initialization — `isRequired = true` and `addValidators(Validators.required)` on the same control is redundant; use one approach |
| COMP-10 | Major | Not using optional chaining — `if (component && component.createPreference)` should be `if (component?.createPreference)`, `this.departmentControl.value && this.departmentControl.value.length > 0` should be `this.departmentControl.value?.length` |
| COMP-11 | Major | Method violates single responsibility — e.g., `setBirthControlInWriteMode()` also disables `deceasedControl` which is unrelated to birth |
| COMP-12 | Major | Hardcoded API URLs in methods — define URLs as `private readonly` constants |
| COMP-13 | Major | Manually calling `setErrors({ required: true })` when `Validators.required` is already added — Angular sets the error automatically when validation fails |
| COMP-14 | Major | Using `setTimeout()` instead of reactive patterns — arbitrary `setTimeout()` delays should be replaced with proper lifecycle hooks or reactive patterns |
| COMP-15 | Minor | Manual date manipulation (`new Date(); setHours(0,0,0,0)`) instead of `startOfDay()` from `date-fns` library |
| COMP-16 | Major | Creating a new component when an existing one can be reused — check existing components before creating new ones |
| COMP-17 | Major | Using `Map` or plain arrays for structured data — use typed value objects/interfaces instead |
| COMP-18 | Major | Multiple similar `@Input()` properties for the same type — use a single `@Input()` and pass different values from the parent template |
| COMP-19 | Major | Reusable logic inline in component — extract common logic to utility files (e.g., `select-option-map-utils.ts`) |

### COMP-01 Detail

```typescript
// BAD — nested if statements
if (this.isOutPatient && this.isDACHL && this.accountingModeControl) {
  if (!this.accountingModeControl.value || this.accountingModeControl.value.length === 0) {
    if (this.accountingModeControl.touched) {
      // error handling
    }
  }
}

// GOOD — single consolidated condition
if (
  this.isOutPatient &&
  this.isDACHL &&
  this.accountingModeControl &&
  (!this.accountingModeControl.value || this.accountingModeControl.value.length === 0) &&
  this.accountingModeControl.touched
) {
  this.accountingModeErrorMessages = this.translations.AccountingModeError;
  medicalCaseErrorMessages.push(this.accountingModeErrorMessages);
  this.accountingModeControl.setErrors({ 'incorrect': true });
  this.isAccountingModeError = true;
}
```

> *PR #752*

### COMP-05 Detail

> "initDACHLControls is called twice. Please call at the place where given patient is outpatient is determined." — *PR #752*

### COMP-06 Detail

> "Why is OnDestroy not handled for this component?" — *PR #804*

### COMP-07 Detail

> "Can you move this method to the contingency.service file" — *PR #804*
>
> "Move to service.ts and add `this.formGroup.addFetchingCall();` and `this.formGroup.fetchingCallFinished();`" — *PR #804*

### COMP-08 Detail

```typescript
// Validator setup and control initialization in constructor
constructor() {
  this.formControl.isRequired = true;
  this.formControl.addValidators(Validators.required);
}

// Data fetching and subscriptions in ngOnInit
ngOnInit(): void {
  this.loadCatalogData();
  this.subscribeToEvents();
}
```

> "Above Both lines Doing Same thing is Required Two times? And move this too constructor level." — *PR #257*

### COMP-09 Detail

```typescript
// BAD — redundant initialization
this.boarderNameControl.isRequired = true;
this.boarderNameControl.addValidators(Validators.required);  // Duplicate

// GOOD — set validators once
this.boarderNameControl.addValidators(Validators.required);
```

### COMP-10 Detail

```typescript
// BAD
if (component && component.createPreference) { ... }
this.departmentControl.value && this.departmentControl.value.length > 0

// GOOD
if (component?.createPreference) { ... }
this.departmentControl.value?.length
```

### COMP-11 Detail

```typescript
// BAD — method handles unrelated concerns
setBirthControlInWriteMode() {
  this.multipleBirthControl.enable();
  this.deceasedControl.disable();  // Unrelated to birth!
}

// GOOD — separate methods for different concerns
setBirthControlInWriteMode() {
  this.multipleBirthControl.enable();
}
setDeathControlInReadMode() {
  this.deceasedControl.disable();
}
```

> "deceasedControl.disable() is related to death section so don't add this in this method because this deals related to MultipleBirth. Add new method to handle it or else Change the method Name - setBirthDeathControlInWriteMode" — *PR #599*

### COMP-12 Detail

```typescript
// BAD — hardcoded URL
public getCaseNumberDefinition(): Observable<Result> {
  let url = environment.pasuPath + '/casenumbers/definitions?active=true';
  return this.getRequest(url, false);
}

// GOOD — URL as constant
private readonly CASE_NUMBER_DEFINITIONS_URL = '/casenumbers/definitions';

public getCaseNumberDefinition(): Observable<Result> {
  const url = `${environment.pasuPath}${this.CASE_NUMBER_DEFINITIONS_URL}?active=true`;
  return this.getRequest(url, false);
}
```

> "define these urls as const" — *PR #764*

### COMP-13 Detail

> "Validators.required is Angular built in validator. Angular sets the { required: true } error automatically on the control when Validators.required fails. You don't need to set it manually" — *PR #599*

### COMP-14 Detail

```typescript
// BAD
setTimeout(() => {
  this.assignBoarderDetails(this.selectedBoarderDetails);
}, 1000);

// GOOD
this.assignBoarderDetails(this.selectedBoarderDetails);
```

> "I think here SetTimeout() Not Required, Pls Check it." — *PR #257*

### COMP-15 Detail

```typescript
// BAD
const today = new Date();
today.setHours(0, 0, 0, 0);

// GOOD
import { startOfDay } from 'date-fns';
const today = startOfDay(new Date());
```

> "Use startOfDay(...) from date-fns library instead." — *PR #599*

### COMP-16 Detail

> "why can't the existing person-domain component be used?" — *PR #474*

### COMP-17 Detail

```typescript
// BAD — using maps for structured data
const caseData = new Map<string, any>();
caseData.set('department', 'Cardiology');

// GOOD — typed value object
interface PersonMergeMedicalCaseValueObject {
  department: string;
  ward: string;
  treatingPhysician: string;
}
const caseData: PersonMergeMedicalCaseValueObject = {
  department: 'Cardiology',
  ward: 'Ward A',
  treatingPhysician: 'Dr. Smith'
};
```

> "please create the person-merge-medical-case-overview-value-object construct the objects of the grid. Don't use map." — *PR #474*
>
> "create person-merge-referral-value-object interface and populate the values. Avoid using maps or arrays to store the data" — *PR #474*

### COMP-18 Detail

```typescript
// BAD — multiple similar inputs
@Input() primaryPatient: Patient;
@Input() secondaryPatient: Patient;

// GOOD — single reusable input
@Input() patient: Patient;

// Usage in parent template:
// <patient-details [patient]="primaryPatient"></patient-details>
// <patient-details [patient]="secondaryPatient"></patient-details>
```

> "use one input property patient and pass primaryPatient/secondary in the template where the component is injected." — *PR #474*

### COMP-19 Detail

> "pls add the logic to create `<SelectOption<OrganizationalUnitView>>` that exists in createOrgaResult method to select-option-map-utils.ts." — *PR #584*

---

## Angular Service Rules (`.service.ts`) — PR Review

| Rule | Severity | Violation |
|------|----------|-----------|
| SVC-01 | Major | Fetch logic moved to service without proper loading state management — must include `formGroup.addFetchingCall()` before and `formGroup.fetchingCallFinished()` after API call |

### SVC-01 Detail

```typescript
this.formGroup.addFetchingCall();
this.service.getData().subscribe({
  next: (data) => {
    this.data = data;
    this.formGroup.fetchingCallFinished();
  },
  error: () => {
    this.formGroup.fetchingCallFinished();
  }
});
```

> "Add this.formGroup.addFetchingCall(); before the call" — *PR #591*

---

## Angular Template Rules (`.component.html`) — PR Review

| Rule | Severity | Violation |
|------|----------|-----------|
| TPL-01 | Minor | Inconsistent HTML alignment — misaligned attributes and tags across template files |
| TPL-02 | Major | New event handler method introduced in template when an existing method already covers the same logic (e.g., `(focusout)="onAccountingModeFocusOut()"` instead of `(focusout)="validateMedicalCase()"`) |
| TPL-03 | Minor | Multiple conditional CSS classes applied with separate `class`/`[class.*]` bindings instead of a single `[ngClass]` object |
| TPL-04 | Major | Multiple `*ngIf` directives on individual sibling elements with the same condition — wrap in a single parent `<div *ngIf>` or `<ng-container *ngIf>` instead |
| TPL-05 | Major | Duplicate HTML blocks that should use `<ng-template>` with `*ngTemplateOutlet` for reuse |

### TPL-01 Detail

> "Check for alignment here and all other places" — *PR #804*
>
> "Alignment check has been done for all case number html files." — *PR #804*

### TPL-02 Detail

```html
<!-- GOOD — reuse existing method -->
(focusout)="validateMedicalCase()"

<!-- BAD — new method duplicating existing behaviour -->
(focusout)="onAccountingModeFocusOut()"
```

### TPL-03 Detail

```html
[ngClass]="{
  'case-number-contingency__grid--value-strikeout': context.value.status === contingencyExpiredStatus,
  'case-number-contingency__grid--value-wrap': true
}"
```

### TPL-04 Detail

```html
<!-- BAD — multiple *ngIf on individual elements -->
<label *ngIf="isWardAttender">...</label>
<input *ngIf="isWardAttender">...</input>

<!-- GOOD — single *ngIf on parent container -->
<div *ngIf="isWardAttender">
  <label>...</label>
  <input>...</input>
</div>
```

> "You can have *ngIf="wardAttenderMode" for the entire div instead of individual elements within the div." — *PR #584*

### TPL-05 Detail

```html
<!-- Define reusable template -->
<ng-template #treatmentCategoryTemplate>
  <pas-form-label [control]="treatmentCategoryControl">...</pas-form-label>
  <pas-catalog-select [control]="treatmentCategoryControl">...</pas-catalog-select>
</ng-template>

<!-- Use in multiple places -->
<ng-container *ngTemplateOutlet="treatmentCategoryTemplate"></ng-container>
```

> "There is code duplication here. Maybe we can try using `<ng-template #treatmentCategoryTemplate>` and call it in both places?" — *PR #584*

---

## Resource & Translation Rules — PR Review

| Rule | Severity | Violation |
|------|----------|-----------|
| RES-01 | Blocker | New resource key added but missing from one or more translation files (`translations_en.ts`, `translations_de.ts`, `translations_en_GB.ts`, `pas_Resources_fr.json`, etc.) |
| RES-02 | Major | Translation designed as region-only solution instead of global solution with region-based conditional visibility |

### RES-01 Detail

> "We can add the same fields in both translations_en_GB.ts and translations_de.ts as well. It's better to include these keys now — it'll be useful when switching or running Karma tests in those regions later." — *PR #599*

---

## Code Cleanup Rules — PR Review

| Rule | Severity | Violation |
|------|----------|-----------|
| CLEAN-01 | Major | Commented-out code present in PR — must be removed before merge (version control preserves history) |
| CLEAN-02 | Blocker | Previously addressed defect fix reverted — changes made as part of defect resolutions must be preserved |
| CLEAN-03 | Major | Unused variables, imports, controls, or styles left in code |
| CLEAN-04 | Major | `console.log` statements left in code — remove before merge |
| CLEAN-05 | Major | Duplicate files exist — keep only in canonical location, remove duplicates |
| CLEAN-06 | Major | Empty or placeholder files with only comments — remove |

### CLEAN-01 Detail

> "remove commented lines" — *PR #804*
>
> "remove commented code" — *PR #804*
>
> "Entire file is commented?" — *PR #804*

### CLEAN-02 Detail

> "Please change it back to `[uTitle]=\"'PAS_PERSON_LABEL_CLOSE'\"`. This was addressed as a part of a defect." — *PR #804*

### CLEAN-03 Detail

> "These 2 controls are not used anywhere." — *PR #584*
>
> "Styles here are unused" — *PR #584*

### CLEAN-04 Detail

> "remove logs and unwanted comments" — *PR #584*

### CLEAN-05 Detail

> "remove this file" (for duplicated files) — *PR #584*

---

## Karma Spec Test Rules (`.spec.ts`) — PR Review

| Rule | Severity | Violation |
|------|----------|-----------|
| KARMA-01 | Major | New resource keys added but test data files (`translations_en.ts`, `translations_de.ts`) not updated — causes spec failures |
| KARMA-02 | Major | Mock data inconsistent with production implementation — leads to false-positive tests |
| KARMA-03 | Major | Redundant fixture/component re-initialization inside individual test — `fixture` and `component` are already created in `beforeEach()` |
| KARMA-04 | Major | Mock data constants not in `ALL_CAPS` — e.g., `mockRelativeHumanBeing` should be `MOCK_RELATIVE_HUMANBEING` |
| KARMA-05 | Major | Multiple separate tests for related assertions that should be a single test — e.g., checking `firstname`, `surname`, `dateOfBirth` in separate tests instead of one |
| KARMA-06 | Major | Incorrect assertion — using `reset()` (equivalent to not called) instead of asserting `toHaveBeenCalledTimes()` or `toHaveBeenCalledWith()` |
| KARMA-07 | Minor | `jasmine.clock().uninstall()` in `afterEach` when `jasmine.clock()` is never used in the test suite |
| KARMA-08 | Minor | Redundant `markAsTouched()` after `apply()` — `apply()` already triggers touch |
| KARMA-09 | Major | Translation locale mismatch — test uses `translateService.use('en_US')` but loads `translations_en_GB.ts` |
| KARMA-10 | Major | Missing test coverage for both branches of boolean conditions — must test both `true` and `false` states |
| KARMA-11 | Major | Shared mock data duplicated across test files — move to common location (`frontend/ui/src/app/common/test-data/` or `cucumber-playwright/src/mocks/common/test-data/`) |

### KARMA-03 Detail

> "fixture and component are already created in the beforeEach(). remove this initialization." — *PR #590*

### KARMA-05 Detail

> "Can we not check if all the details are populated when valid pid is entered in a single test?" — *PR #590*

### KARMA-06 Detail

> "not sure what has been tested here. reset() is equivalent to method not been called. to assert on number of times the service call is been made." — *PR #474*

### KARMA-07 Detail

> "what is the use of uninstall when there is no usage of jasmine mock clock?" — *PR #590*

### KARMA-08 Detail

> "apply method is already called. remove the markAsTouched()" — *PR #590*

### KARMA-09 Detail

> "Translation resource is loaded for 'en_GB' and here initialized for en_US?" — *PR #584*

### KARMA-10 Detail

> "please cover 2 unit tests for your usecase scenario: 1. ward attender mode=false and check for the controls to be present for outpatient 2. ward attender mode=true and check for the controls to be present" — *PR #584*

### KARMA-11 Detail

> "this file is duplicated. please move this file to the location cucumber-playwright/src/mocks/common/test-data" — *PR #584*

---

## Playwright Test Rules — PR Review

| Rule | Severity | Violation |
|------|----------|-----------|
| PW-01 | Major | Feature behaviour modified but corresponding Playwright tests not updated |
| PW-02 | Major | Region-specific test conditions not properly handled using `TestEnvironment.isCountryCode()` utilities |

### PW-01 Detail

> "Pls also modify the playwright tests related to contingency." — *PR #807*

### PW-02 Detail

```typescript
if (
  !TestEnvironment.isCountryCode(CountryGroup.DACHL) &&
  !TestEnvironment.isCountryCode(CountryCode.FR)
) {
  // Skip or adjust tests for non-applicable regions
}
```

---

## Cucumber Test Rules — PR Review

| Rule | Severity | Violation |
|------|----------|-----------|
| CUC-01 | Major | Feature behaviour modified but Cucumber step definitions not updated — causes integration test failures |
| CUC-02 | Major | Country code checks missing or incorrect in step definitions for region-specific features — use same utilities as Playwright tests |

---

## Logic & Architecture Rules — PR Review

| Rule | Severity | Violation |
|------|----------|-----------|
| ARCH-01 | Major | Unnecessary `if-else` when both branches execute similar logic — consolidate into single path |
| ARCH-02 | Minor | Redundant variable assigned multiple times without clear purpose — each variable should have a single, well-defined responsibility |

### ARCH-01 Detail

> "Do we need if-else here? Can we not handle it in the same way for both?" — *PR #804*

### ARCH-02 Detail

> "Why do we need eventType for multiple assignments?" — *PR #804*


## Summary Checklist

| Category | Rules | Key Points |
|---|---|---|
| **Naming** | NAME-01 to NAME-10 | Full descriptive names, `is` prefix for booleans, `ALL_CAPS` for constants, meaningful method names, enums over string literals, `data-e2e-id` for test attributes |
| **Components** | COMP-01 to COMP-19 | Simplify conditionals, use optional chaining, single responsibility, validators in constructor, no `setTimeout`, use `date-fns`, value objects over maps, reuse existing components, extract utilities |
| **Services** | SVC-01 | Include loading state management (`addFetchingCall` / `fetchingCallFinished`) in both success and error paths |
| **Templates** | TPL-01 to TPL-05 | Check alignment, use existing methods, optimize `ngClass`, consolidate `*ngIf`, use `ng-template` for duplication |
| **Resources** | RES-01 to RES-02 | Update **all** translation files including for future region/Karma test use, design for global use |
| **Cleanup** | CLEAN-01 to CLEAN-06 | Remove commented code, unused variables/imports/controls/styles, `console.log`, duplicate files, preserve defect fixes |
| **Karma Tests** | KARMA-01 to KARMA-11 | No redundant init, `ALL_CAPS` mocks, combine related assertions, proper spy assertions, correct locale, test both branches, shared mock data in common location |
| **Playwright Tests** | PW-01 to PW-02 | Update tests for feature changes, handle region-specific conditions properly |
| **Cucumber Tests** | CUC-01 to CUC-02 | Update step definitions, implement country/region checks |
| **Logic & Architecture** | ARCH-01 to ARCH-02 | Simplify conditionals, avoid redundant variables |

---

> **Source**: Review comments from PRs #257, #297, #474, #584, #590, #591, #599, #752, #764, #776, #804, #807 in the `dedalus-cis4u/pas-ou` repository.
