/* eslint-disable security/detect-non-literal-regexp */
const navigatePath = (obj, paths = []) => {
  for (const path of paths) {
    // eslint-disable-next-line security/detect-object-injection
    const nextPath = obj[path]
    // eslint-disable-next-line no-param-reassign
    obj = nextPath
    if (obj === undefined) {
      break
    }
  }
  return obj
}

const typeOfConsideringNullAndArray = (obj) => {
  if (obj === null) {
    return 'null'
  }
  if (Array.isArray(obj)) {
    return 'array'
  }
  return typeof obj
}

/**
 * Returns true if not present and not required
 * @param {*} obj
 * @param {String[]} requiredProps
 * @param {String[]} currentPaths
 */
const notPresentAndNotRequired = (obj, requiredProps, currentPaths) => obj === undefined && requiredProps && !requiredProps.includes(currentPaths[currentPaths.length - 1])

const isReallyAnObj = (obj) => typeof obj === 'object' && obj !== null && !Array.isArray(obj)
/**
 * @param {String[]} paths
 * @param {any} p
 * @returns {Function[]}
 */
const getValidations = (paths, p, requiredProps) => {
  if (!p) return []
  const validations = []
  const currentPaths = [...paths]
  if (p.type === 'object') {
    const currentKeys = Object.keys(p.properties || [])
    validations.push((obj) => {
      const currPointer = navigatePath(obj, currentPaths)
      if (notPresentAndNotRequired(currPointer, requiredProps, currentPaths)) {
        return null
      }
      if (isReallyAnObj(currPointer)) {
        return null
      }
      return {
        message: `Invalid type. Expected object but got ${typeOfConsideringNullAndArray(currPointer)}`,
        schemaPath: `#${currentPaths.map((c) => `/properties/${c}`).join('')}/type`,
      }
    })
    if (p.additionalProperties === false) {
      validations.push((obj) => {
        const currPointer = navigatePath(obj, currentPaths)
        if (notPresentAndNotRequired(currPointer, requiredProps, currentPaths)) {
          return null
        }
        const objKeys = Object.keys(currPointer)
        for (const objKey of objKeys) {
          if (!currentKeys.includes(objKey)) {
            return {
              message: `Property '${objKey}' has not been defined and the schema does not allow additional properties.`,
              schemaPath: `#${currentPaths.map((c) => `/properties/${c}`).join('')}/additionalProperties`,
            }
          }
        }
        return null
      })
    }
    if (Array.isArray(p.required) && p.required.length) {
      validations.push((obj) => {
        const currPointer = navigatePath(obj, currentPaths)
        if (notPresentAndNotRequired(currPointer, requiredProps, currentPaths)) {
          return null
        }
        for (const requiredProperty of p.required) {
          // eslint-disable-next-line security/detect-object-injection
          if (!Object.prototype.hasOwnProperty.call(currPointer, requiredProperty) || currPointer[requiredProperty] === undefined) {
            return {
              message: `Required properties are missing from object: ${requiredProperty}`,
              schemaPath: `#${currentPaths.map((c) => `/properties/${c}`).join('')}/required`,
            }
          }
        }
        return null
      })
    }
    for (const key of currentKeys) {
      validations.push(...getValidations([...currentPaths, key], p.properties[String(key)], p.required || []))
    }
  } else if (p.type === 'number') {
    validations.push((obj) => {
      const currPointer = navigatePath(obj, currentPaths)
      if (notPresentAndNotRequired(currPointer, requiredProps, currentPaths)) {
        return null
      }
      const typeofCurrPointer = typeof currPointer
      if ((typeofCurrPointer === 'number' || (typeofCurrPointer === 'string' && currPointer !== ''))) {
        const casted = Number(currPointer)
        if (Number.isFinite(casted)) {
          return null
        }
        if (Number.isNaN(currPointer)) {
          return {
            message: 'Invalid type. Expected number but got NaN',
            schemaPath: `#${currentPaths.map((c) => `/properties/${c}`).join('')}/type`,
          }
        }
        if (casted === Number.POSITIVE_INFINITY || casted === Number.NEGATIVE_INFINITY) {
          return {
            message: 'Invalid type. Expected number but got infinity',
            schemaPath: `#${currentPaths.map((c) => `/properties/${c}`).join('')}/type`,
          }
        }
      }

      return {
        message: `Invalid type. Expected number but got ${typeOfConsideringNullAndArray(currPointer)}`,
        schemaPath: `#${currentPaths.map((c) => `/properties/${c}`).join('')}/type`,
      }
    })
  } else if (p.type === 'string') {
    let pattern
    if (p.pattern) {
      pattern = new RegExp(p.pattern)
    }
    validations.push((obj) => {
      const currPointer = navigatePath(obj, currentPaths)
      if (notPresentAndNotRequired(currPointer, requiredProps, currentPaths)) {
        return null
      }
      if (typeof currPointer === 'string') {
        if (pattern && !pattern.test(currPointer)) {
          return {
            message: `String '${currPointer}' does not match regex pattern '${p.pattern}'.`,
            schemaPath: `#${currentPaths.map((c) => `/properties/${c}`).join('')}/pattern`,
          }
        }
        return null
      }
      return {
        message: `Invalid type. Expected string but got ${typeOfConsideringNullAndArray(currPointer)}`,
        schemaPath: `#${currentPaths.map((c) => `/properties/${c}`).join('')}/type`,
      }
    })
  } else if (p.type === 'boolean') {
    validations.push((obj) => {
      const currPointer = navigatePath(obj, currentPaths)
      if (notPresentAndNotRequired(currPointer, requiredProps, currentPaths)) {
        return null
      }
      if (typeof currPointer === 'boolean') {
        return null
      }
      return {
        message: `Invalid type. Expected boolean but got ${typeOfConsideringNullAndArray(currPointer)}`,
        schemaPath: `#${currentPaths.map((c) => `/properties/${c}`).join('')}/type`,
      }
    })
  }
  return validations
}

/**
 * Returns an object validator, based on json-schema
 * @param {*} schema
 * @returns {(input:any) => false|{message:string,schemaPath:string}}
 */
export const getValidator = (schema) => {
  const validations = getValidations([], schema)
  return (obj) => {
    for (const validation of validations) {
      const err = validation(obj)
      if (err) {
        return err
      }
    }
    return false
  }
}
