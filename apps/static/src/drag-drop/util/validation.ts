// Validation
export interface Validatable {
  value: string | number;
  required?: boolean;
  minLength?: number;
  maxLength?: number;
  min?: number;
  max?: number;
}

export function validate(validatableInput: Validatable) {
  if (validatableInput.required && validatableInput.value.toString().trim().length === 0) {
    return false;
  }
  if (validatableInput.minLength != null && typeof validatableInput.value === 'string' && validatableInput.value.length < validatableInput.minLength) {
    return false;
  }
  if (validatableInput.maxLength != null && typeof validatableInput.value === 'string' && validatableInput.value.length > validatableInput.maxLength) {
    return false;
  }
  if (validatableInput.min != null && typeof validatableInput.value === 'number' && validatableInput.value < validatableInput.min) {
    return false;
  }
  if (validatableInput.max != null && typeof validatableInput.value === 'number' && validatableInput.value > validatableInput.max) {
    return false;
  }
  return true;
}
