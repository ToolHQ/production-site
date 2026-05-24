const navigatePath = (obj, paths = []) => {
  for (const path of paths) {
    obj = obj[path]
    if (obj === undefined) {
      break
    }
  }
  return obj
}

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
    validations.push(obj => {
      const currPointer = navigatePath(obj, currentPaths)
      if (currPointer === undefined && requiredProps && !requiredProps.includes(currentPaths[currentPaths.length - 1])) {
        return null
      }
      if (!Array.isArray(currPointer) && typeof currPointer === 'object' && currPointer !== null) {
        return null
      } else {
        return {
          message: `Invalid type. Expected object but got ${currPointer === null ? null : (Array.isArray(currPointer) ? 'array' : typeof currPointer)}`,
          schemaPath: '#' + currentPaths.map(c => `/properties/${c}`).join('') + '/type'
        }
      }
    })
    if (p.additionalProperties === false) {
      validations.push(obj => {
        const currPointer = navigatePath(obj, currentPaths)
        if (currPointer === undefined && requiredProps && !requiredProps.includes(currentPaths[currentPaths.length - 1])) {
          return null
        }
        const objKeys = Object.keys(currPointer)
        for (const objKey of objKeys) {
          if (!currentKeys.includes(objKey)) {
            return {
              message: `Property '${objKey}' has not been defined and the schema does not allow additional properties.`,
              schemaPath: '#' + currentPaths.map(c => `/properties/${c}`).join('') + '/additionalProperties'
            }
          }
        }
        return null
      })
    }
    if (Array.isArray(p.required) && p.required.length) {
      validations.push(obj => {
        const currPointer = navigatePath(obj, currentPaths)
        if (currPointer === undefined && requiredProps && !requiredProps.includes(currentPaths[currentPaths.length - 1])) {
          return null
        }
        for (const requiredProperty of p.required) {
          if (!Object.prototype.hasOwnProperty.call(currPointer, requiredProperty) || currPointer[requiredProperty] === undefined) {
            return {
              message: `Required properties are missing from object: ${requiredProperty}`,
              schemaPath: '#' + currentPaths.map(c => `/properties/${c}`).join('') + '/required'
            }
          }
        }
        return null
      })
    }
    for (const key of currentKeys) {
      validations.push(...getValidations([...currentPaths, key], p.properties[key], p.required || []))
    }
  } else if (p.type === 'number') {
    validations.push(obj => {
      const currPointer = navigatePath(obj, currentPaths)
      if (currPointer === undefined && requiredProps && !requiredProps.includes(currentPaths[currentPaths.length - 1])) {
        return null
      }
      if ((typeof currPointer === 'number' || (typeof currPointer === 'string' && currPointer !== '')) && !isNaN(currPointer)) {
        return null
      } else {
        return {
          message: `Invalid type. Expected number but got ${currPointer === null ? null : (Array.isArray(currPointer) ? 'array' : typeof currPointer)}`,
          schemaPath: '#' + currentPaths.map(c => `/properties/${c}`).join('') + '/type'
        }
      }
    })
  } else if (p.type === 'string') {
    let pattern
    if (p.pattern) {
      pattern = new RegExp(p.pattern)
    }
    validations.push(obj => {
      const currPointer = navigatePath(obj, currentPaths)
      if (currPointer === undefined && requiredProps && !requiredProps.includes(currentPaths[currentPaths.length - 1])) {
        return null
      }
      if (typeof currPointer === 'string') {
        if (pattern && !pattern.test(currPointer)) {
          return {
            message: `String '${currPointer}' does not match regex pattern '${p.pattern}'.`,
            schemaPath: '#' + currentPaths.map(c => `/properties/${c}`).join('') + '/pattern'
          }
        }
        return null
      } else {
        return {
          message: `Invalid type. Expected string but got ${currPointer === null ? null : (Array.isArray(currPointer) ? 'array' : typeof currPointer)}`,
          schemaPath: '#' + currentPaths.map(c => `/properties/${c}`).join('') + '/type'
        }
      }
    })
  } else if (p.type === 'boolean') {
    validations.push(obj => {
      const currPointer = navigatePath(obj, currentPaths)
      if (currPointer === undefined && requiredProps && !requiredProps.includes(currentPaths[currentPaths.length - 1])) {
        return null
      }
      if (typeof currPointer === 'boolean') {
        return null
      } else {
        return {
          message: `Invalid type. Expected boolean but got ${currPointer === null ? null : (Array.isArray(currPointer) ? 'array' : typeof currPointer)}`,
          schemaPath: '#' + currentPaths.map(c => `/properties/${c}`).join('') + '/type'
        }
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
export const getValidator = schema => {
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
