// Thin native-view adapter over @openuidev/lang-core 1.1.1 (MIT).
// Parser, evaluator, reactive assignment, query cache and mutation execution are
// upstream; no OpenUI grammar or expression interpreter is implemented here.
import {
  createStreamingParser, createStore, createQueryManager, evaluate,
  evaluateRoot, evaluateElementProps, isElementNode, resolveStateField,
  parseStructuredRules, validate,
} from '@openuidev/lang-core';

const unwrap = value => value && typeof value === 'object' && 'componentType' in value ? value.value : value;
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);

export class NativeRuntime {
  constructor({ library, toolProvider, onTree, onState, onAction, onError }) {
    this.library = library;
    this.schema = library.toJSONSchema();
    this.parser = createStreamingParser(this.schema, library.root);
    this.store = createStore();
    this.queries = createQueryManager(toolProvider);
    this.onTree = onTree; this.onState = onState; this.onAction = onAction; this.onError = onError;
    this.fields = new Map(); this.actions = new Map(); this.errors = new Map(); this.stream = true; this.hydrating = false;
    this.context = {
      getState: name => unwrap(this.store.get(name)),
      resolveRef: name => this.queries.getMutationResult(name) ?? this.queries.getResult(name),
      functions: Object.fromEntries(Object.entries(this.schema.functions ?? {}).flatMap(([name, schema]) => {
        const fn = library.functions?.[name]?.fn;
        return fn ? [[name, { ...schema, fn }]] : [];
      })),
      actions: this.schema.actions,
    };
    this.evalContext = { ctx: this.context, library, store: this.store };
    this.lastState = {};
    this.subscriptions = [
      this.store.subscribe(() => {
        const state = this.store.getSnapshot();
        const previous = this.lastState;
        this.lastState = state;
        if (!this.hydrating && !equal(state, previous)) this.onState?.(state, previous);
        this.schedule();
      }),
      this.queries.subscribe(() => this.schedule()),
    ];
    this.queries.activate();
  }

  update(program, complete, state) {
    this.stream = !complete;
    this.result = this.parser.set(program, complete);
    this.hydrating = true;
    const variables = {};
    for (const [name, value] of Object.entries(state ?? {})) {
      if (name.startsWith('$')) variables[name] = value;
      else if (!equal(value, this.store.get(name))) this.store.set(name, value);
    }
    this.store.initialize(this.result.stateDeclarations ?? {}, variables);
    this.lastState = this.store.getSnapshot();
    this.hydrating = false;
    // Newly declared defaults belong to the shared message as well.
    if (!equal(this.lastState, state ?? {})) this.onState?.(this.lastState, state ?? {});
    this.render();
  }

  schedule() {
    if (this.scheduled || this.disposed) return;
    this.scheduled = true;
    queueMicrotask(() => { this.scheduled = false; if (!this.disposed) this.render(); });
  }

  render() {
    if (!this.result) return;
    if (!this.stream) {
      this.queries.registerMutations((this.result.mutationStatements ?? []).map(m => ({
        statementId: m.statementId, toolName: m.toolAST ? evaluate(m.toolAST, this.context) : '',
      })));
      this.queries.evaluateStatements(this.result.queryStatements ?? [], this.context);
    }
    this.fields.clear(); this.actions.clear();
    const root = evaluateRoot(this.result, this.evalContext);
    this.onTree?.(this.visit(root, 'root', null));
    if (!this.stream && this.result.meta.errors?.length) this.onError?.(this.result.meta.errors.map(e => e.message).join('\n'));
  }

  visit(value, path, formName) {
    if (Array.isArray(value)) return value.map((child, i) => this.visit(child, `${path}/${i}`, formName));
    if (isElementNode(value)) {
      const el = evaluateElementProps(value, this.evalContext);
      const id = el.statementId ? `${path}/${el.statementId}` : path;
      const form = el.typeName === 'Form' ? el.props.name : formName;
      const props = {};
      for (const [key, prop] of Object.entries(el.props)) {
        if (key === 'action') {
          this.actions.set(id, { action: prop, formName: form, label: el.props.label ?? el.props.title ?? el.props.name ?? '',
            primaryButton: el.typeName === 'Button' && (el.props.variant ?? 'primary') === 'primary' });
          props.hasAction = true; continue;
        }
        props[key] = this.visit(prop, `${id}/${key}`, form);
      }
      if (el.typeName === 'Button' && !this.actions.has(id)) {
        this.actions.set(id, { action: undefined, formName: form, label: el.props.label ?? '',
          primaryButton: (el.props.variant ?? 'primary') === 'primary' });
      }
      const fieldTypes = ['Input', 'TextArea', 'Select', 'DatePicker', 'Slider', 'CheckBoxGroup', 'RadioGroup', 'SwitchGroup', 'Chips', 'OptionCards', 'EditableTable'];
      if (fieldTypes.includes(el.typeName)) {
        const field = resolveStateField(el.props.name ?? id, el.props.value, this.store, this.context,
          name => unwrap(form ? this.store.get(form)?.[name] : this.store.get(name)),
          (name, next) => {
            const wrapped = { value: next, componentType: el.typeName };
            if (form) this.store.set(form, { ...(this.store.get(form) ?? {}), [name]: wrapped });
            else this.store.set(name, wrapped);
          });
        this.fields.set(id, { ...field, formName: form, rules: parseStructuredRules(el.props.rules) });
        props.currentValue = field.value ?? el.props.defaultValue ?? null;
        props.validationError = this.errors.get(id) ?? null;
      }
      if (el.typeName === 'Modal') {
        const field = resolveStateField(`${id}/open`, el.props.open, this.store, this.context,
          name => unwrap(this.store.get(name)), (name, next) => this.store.set(name, next));
        this.fields.set(id, field); props.open = field.value ?? false;
      }
      return { id, typeName: el.typeName, props, partial: el.partial, enabled: !this.stream };
    }
    if (value instanceof Date) return value;
    if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, this.visit(v, `${path}/${k}`, formName)]));
    return value ?? null;
  }

  setField(id, value) {
    if (this.stream) return;
    const field = this.fields.get(id);
    if (!field) return;
    field.setValue(value);
    if (field.rules?.length && field.formName) {
      const error = validate(value, field.rules);
      if (error) this.errors.set(id, error); else this.errors.delete(id);
      this.schedule();
    }
  }

  async act(id) {
    if (this.stream) return;
    const entry = this.actions.get(id);
    if (!entry) return;
    const { action, label, formName } = entry;
    // Match the original Button's primary-submit policy and use the original
    // core validators. Local Set/Reset actions remain available to repair fields.
    const needsValidation = !action?.steps || action.steps.some(step =>
      step.type === 'continue_conversation' || step.type === 'custom_action' ||
      (step.type === 'run' && step.refType === 'mutation'));
    if (formName && entry.primaryButton && needsValidation) {
      let valid = true;
      for (const [fieldID, field] of this.fields) {
        if (field.formName !== formName || !field.rules?.length) continue;
        const error = validate(field.value, field.rules);
        if (error) { this.errors.set(fieldID, error); valid = false; }
        else this.errors.delete(fieldID);
      }
      this.schedule();
      if (!valid) return;
    }
    const formPayload = () => {
      const form = formName ? this.store.get(formName) : undefined;
      return form && typeof form === 'object' && !Array.isArray(form)
        ? { [formName]: form } : this.store.getSnapshot();
    };
    const emit = (type, params = {}, message = '') => this.onAction?.({ type, params, humanFriendlyMessage: message, formName, formState: formPayload() });
    // Action plans are produced by the original parser. These are the same
    // runtime operations used by the original React adapter (MIT); host effects
    // always return through the injected original Hanlin Host adapter.
    if (!action?.steps) {
      const params = { ...(action?.params ?? {}) };
      if (action?.url) params.url = action.url;
      if (action?.context) params.context = action.context;
      await emit(action?.type ?? 'continue_conversation', params, label); return;
    }
    for (const step of action.steps) {
      switch (step.type) {
        case 'run':
          if (step.refType === 'mutation') {
            const mutation = this.result.mutationStatements.find(m => m.statementId === step.statementId);
            if (!await this.queries.fireMutation(step.statementId, mutation?.argsAST ? evaluate(mutation.argsAST, this.context) : {})) return;
          } else this.queries.invalidate([step.statementId]);
          break;
        case 'continue_conversation': await emit(step.type, step.context === undefined ? {} : { context: step.context }, step.message); break;
        case 'open_url': await emit(step.type, { url: step.url }); break;
        case 'custom_action': await emit(step.name, step.params); break;
        case 'set': if (step.valueAST) this.store.set(step.target, evaluate(step.valueAST, this.context)); break;
        case 'reset': for (const target of step.targets) this.store.set(target, this.result.stateDeclarations?.[target] ?? null, { pristine: true }); break;
      }
    }
  }

  dispose() {
    this.disposed = true;
    for (const unsubscribe of this.subscriptions) unsubscribe();
    this.queries.dispose(); this.store.dispose();
  }
}
