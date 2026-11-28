// model/index.ts — Re-export everything
export * from "./types"
export * from "./constants"
export * from "./storage"
export * from "./icons"
export * from "./i18n"
export * from "./customConfig"
// Explicitly export new AI toggle functions from storage
import {
  isAIProcessingEnabled,
  setAIProcessingEnabled,
  isAIGeneralProcessingEnabled,
  setAIGeneralProcessingEnabled,
  isAIMealMenuCreationEnabled,
  setAIMealMenuCreationEnabled,
  isAIProcessingActive,
  isMealMenuCreationActive,
} from "./storage"

export {
  isAIProcessingEnabled,
  setAIProcessingEnabled,
  isAIGeneralProcessingEnabled,
  setAIGeneralProcessingEnabled,
  isAIMealMenuCreationEnabled,
  setAIMealMenuCreationEnabled,
  isAIProcessingActive,
  isMealMenuCreationActive,
}