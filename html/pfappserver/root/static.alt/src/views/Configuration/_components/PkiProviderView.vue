<template>
  <pf-config-view
    :isLoading="isLoading"
    :disabled="isLoading"
    :form="getForm"
    :model="form"
    :vuelidate="$v.form"
    :isNew="isNew"
    :isClone="isClone"
    @validations="setValidations($event)"
    @close="close"
    @create="create"
    @save="save"
    @remove="remove"
  >
    <template slot="header" is="b-card-header">
      <b-button-close @click="close" v-b-tooltip.hover.left.d300 :title="$t('Close [ESC]')"><icon name="times"></icon></b-button-close>
      <h4 class="d-inline mb-0">
        <span v-if="!isNew && !isClone">{{ $t('PKI Provider {id}', { id: id }) }}</span>
        <span v-else-if="isClone">{{ $t('Clone PKI Provider {id}', { id: id }) }}</span>
        <span v-else>{{ $t('New PKI Provider') }}</span>
      </h4>
      <b-badge class="ml-2" variant="secondary" v-t="providerType"></b-badge>
    </template>
    <template slot="footer"
      scope="{isDeletable}"
    >
      <b-card-footer @mouseenter="$v.form.$touch()">
        <pf-button-save :disabled="invalidForm" :isLoading="isLoading">
          <template v-if="isNew">{{ $t('Create') }}</template>
          <template v-else-if="isClone">{{ $t('Clone') }}</template>
          <template v-else-if="ctrlKey">{{ $t('Save & Close') }}</template>
          <template v-else>{{ $t('Save') }}</template>
        </pf-button-save>
        <pf-button-delete v-if="isDeletable" class="ml-1" :disabled="isLoading" :confirm="$t('Delete PKI Provider?')" @on-delete="remove()"/>
        <b-button :disabled="isLoading" class="ml-1" variant="outline-primary" @click="init()">{{ $t('Reset') }}</b-button>
      </b-card-footer>
    </template>
  </pf-config-view>
</template>

<script>
import pfConfigView from '@/components/pfConfigView'
import pfButtonSave from '@/components/pfButtonSave'
import pfButtonDelete from '@/components/pfButtonDelete'
import pfMixinCtrlKey from '@/components/pfMixinCtrlKey'
import pfMixinEscapeKey from '@/components/pfMixinEscapeKey'
import {
  pfConfigurationDefaultsFromMeta as defaults
} from '@/globals/configuration/pfConfiguration'
import {
  pfConfigurationPkiProviderViewFields as fields
} from '@/globals/configuration/pfConfigurationPkiProviders'
const { validationMixin } = require('vuelidate')

export default {
  name: 'PkiProviderView',
  mixins: [
    validationMixin,
    pfMixinCtrlKey,
    pfMixinEscapeKey
  ],
  components: {
    pfConfigView,
    pfButtonSave,
    pfButtonDelete
  },
  props: {
    storeName: { // from router
      type: String,
      default: null,
      required: true
    },
    providerType: { // from router (or source)
      type: String,
      default: null
    },
    isNew: { // from router
      type: Boolean,
      default: false
    },
    isClone: { // from router
      type: Boolean,
      default: false
    },
    id: { // from router
      type: String,
      default: null
    }
  },
  data () {
    return {
      form: {}, // will be overloaded with the data from the store
      formValidations: {}, // will be overloaded with data from the pfConfigView,
      options: {}
    }
  },
  validations () {
    return {
      form: this.formValidations
    }
  },
  computed: {
    isLoading () {
      return this.$store.getters[`${this.storeName}/isLoading`]
    },
    invalidForm () {
      return this.$v.$invalid || this.$store.getters[`${this.storeName}/isWaiting`]
    },
    getForm () {
      return {
        labelCols: 3,
        fields: fields(this)
      }
    },
    isDeletable () {
      if (this.isNew || this.isClone || ('not_deletable' in this.form && this.form.not_deletable)) {
        return false
      }
      return true
    }
  },
  methods: {
    init () {
      if (this.id) {
        // existing
        this.$store.dispatch(`${this.storeName}/optionsById`, this.id).then(options => {
          this.options = JSON.parse(JSON.stringify(options)) // store options
          this.$store.dispatch(`${this.storeName}/getPkiProvider`, this.id).then(form => {
            this.form = JSON.parse(JSON.stringify(form)) // set form
            this.providerType = form.type
          })
        })
      } else {
        // new
        this.$store.dispatch(`${this.storeName}/optionsByProviderType`, this.providerType).then(options => {
          this.options = JSON.parse(JSON.stringify(options)) // store options
          this.form = defaults(options.meta) // set defaults
          this.form.type = this.providerType
        })
      }
    },
    close (event) {
      this.$router.push({ name: 'pki_providers' })
    },
    create (event) {
      const ctrlKey = this.ctrlKey
      this.$store.dispatch(`${this.storeName}/createPkiProvider`, this.form).then(response => {
        if (ctrlKey) { // [CTRL] key pressed
          this.close()
        } else {
          this.$router.push({ name: 'pki_provider', params: { id: this.form.id } })
        }
      })
    },
    save (event) {
      const ctrlKey = this.ctrlKey
      this.$store.dispatch(`${this.storeName}/updatePkiProvider`, this.form).then(response => {
        if (ctrlKey) { // [CTRL] key pressed
          this.close()
        }
      })
    },
    remove (event) {
      this.$store.dispatch(`${this.storeName}/deletePkiProvider`, this.id).then(response => {
        this.close()
      })
    },
    setValidations (validations) {
      this.$set(this, 'formValidations', validations)
    }
  },
  created () {
    this.init()
  }
}
</script>