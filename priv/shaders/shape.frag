#version 410 core
struct ShapeUniformsData {
    vec4 fill_color;
    vec4 fill_color1;
    vec4 stroke_color;
    vec4 radii;
    vec4 rect;
    vec4 gradient;
    vec4 wedge;
    vec2 viewport;
    vec2 arc;
    float stroke_width;
    float shape;
    float gradient_kind;
    float inset;
    float pixel_scale;
};
struct ShapeUniformsBlock {
    ShapeUniformsData data;
};
struct VertexOutput {
    vec2 member;
    vec4 member_1;
};
vec2 v_local_1 = vec2(0.0);

layout(std140) uniform ShapeUniforms { ShapeUniformsBlock u; };

vec4 output_ = vec4(0.0);

smooth in vec2 _vs2fs_location0;
layout(location = 0) out vec4 _fs2p_location0;

void function() {
    float phi_100_ = 0.0;
    float phi_121_ = 0.0;
    float phi_129_ = 0.0;
    int phi_150_ = 0;
    float phi_153_ = 0.0;
    int phi_169_ = 0;
    int phi_151_ = 0;
    float phi_154_ = 0.0;
    bool phi_171_ = false;
    float phi_176_ = 0.0;
    int phi_213_ = 0;
    float phi_216_ = 0.0;
    int phi_232_ = 0;
    int phi_214_ = 0;
    float phi_217_ = 0.0;
    bool phi_234_ = false;
    float phi_239_ = 0.0;
    int phi_252_ = 0;
    float phi_255_ = 0.0;
    int phi_271_ = 0;
    int phi_253_ = 0;
    float phi_256_ = 0.0;
    bool phi_273_ = false;
    float phi_278_ = 0.0;
    float phi_289_ = 0.0;
    float phi_293_ = 0.0;
    float phi_294_ = 0.0;
    float phi_295_ = 0.0;
    bool phi_296_ = false;
    int phi_308_ = 0;
    float phi_311_ = 0.0;
    int phi_327_ = 0;
    int phi_309_ = 0;
    float phi_312_ = 0.0;
    bool phi_329_ = false;
    float phi_334_ = 0.0;
    float phi_335_ = 0.0;
    float phi_370_ = 0.0;
    int phi_379_ = 0;
    float phi_382_ = 0.0;
    int phi_398_ = 0;
    int phi_380_ = 0;
    float phi_383_ = 0.0;
    bool phi_400_ = false;
    float phi_405_ = 0.0;
    float phi_419_ = 0.0;
    int phi_432_ = 0;
    float phi_435_ = 0.0;
    int phi_451_ = 0;
    int phi_433_ = 0;
    float phi_436_ = 0.0;
    bool phi_453_ = false;
    float phi_458_ = 0.0;
    float phi_467_ = 0.0;
    float phi_490_ = 0.0;
    int phi_505_ = 0;
    float phi_508_ = 0.0;
    int phi_524_ = 0;
    int phi_506_ = 0;
    float phi_509_ = 0.0;
    bool phi_526_ = false;
    float phi_531_ = 0.0;
    float phi_538_ = 0.0;
    int phi_551_ = 0;
    float phi_554_ = 0.0;
    int phi_570_ = 0;
    int phi_552_ = 0;
    float phi_555_ = 0.0;
    bool phi_572_ = false;
    float phi_577_ = 0.0;
    float phi_578_ = 0.0;
    float phi_580_ = 0.0;
    float phi_581_ = 0.0;
    float phi_582_ = 0.0;
    float phi_634_ = 0.0;
    float phi_635_ = 0.0;
    int phi_659_ = 0;
    float phi_662_ = 0.0;
    int phi_678_ = 0;
    int phi_660_ = 0;
    float phi_663_ = 0.0;
    bool phi_680_ = false;
    float phi_685_ = 0.0;
    float phi_696_ = 0.0;
    float phi_697_ = 0.0;
    float phi_698_ = 0.0;
    float phi_699_ = 0.0;
    float phi_743_ = 0.0;
    float phi_759_ = 0.0;
    float phi_772_ = 0.0;
    float phi_777_ = 0.0;
    float local = 0.0;
    float local_1 = 0.0;
    float local_2 = 0.0;
    float local_3 = 0.0;
    float local_4 = 0.0;
    float local_5 = 0.0;
    float local_6 = 0.0;
    float local_7 = 0.0;
    float local_8 = 0.0;
    vec2 _e35 = v_local_1;
    float _e41 = u.data.rect[2u];
    float _e42 = (_e41 * 0.5);
    float _e46 = u.data.rect[3u];
    float _e47 = (_e46 * 0.5);
    float _e50 = u.data.shape;
    if ((_e50 < 0.5)) {
        float _e55 = u.data.radii[0u];
        float _e59 = u.data.radii[1u];
        float _e63 = u.data.radii[2u];
        float _e67 = u.data.radii[3u];
        bool _e68 = (_e35.y < 0.0);
        if (_e68) {
            phi_100_ = ((_e35.x < 0.0) ? _e55 : _e59);
        } else {
            phi_100_ = ((_e35.x < 0.0) ? _e67 : _e63);
        }
        float _e74 = phi_100_;
        float _e76 = ((_e42 < _e47) ? _e42 : _e47);
        float _e78 = ((_e74 > _e76) ? _e76 : _e74);
        float _e80 = ((_e78 < 0.0) ? 0.0 : _e78);
        if ((_e35.x < 0.0)) {
            phi_121_ = -(_e35.x);
        } else {
            phi_121_ = _e35.x;
        }
        float _e84 = phi_121_;
        float _e86 = ((_e84 - _e42) + _e80);
        if (_e68) {
            phi_129_ = -(_e35.y);
        } else {
            phi_129_ = _e35.y;
        }
        float _e89 = phi_129_;
        float _e91 = ((_e89 - _e47) + _e80);
        float _e93 = ((_e86 > 0.0) ? _e86 : 0.0);
        float _e95 = ((_e91 > 0.0) ? _e91 : 0.0);
        float _e98 = ((_e93 * _e93) + (_e95 * _e95));
        if ((_e98 <= 0.0)) {
            phi_176_ = 0.0;
        } else {
            phi_150_ = 0;
            phi_153_ = _e98;
            bool loop_init = true;
            while(true) {
                if (!loop_init) {
                    phi_150_ = phi_151_;
                    phi_153_ = phi_154_;
                    if (!(phi_171_)) {
                        break;
                    }
                }
                loop_init = false;
                int _e101 = phi_150_;
                float _e103 = phi_153_;
                local = _e103;
                if ((_e101 < 20)) {
                    float _e107 = (0.5 * (_e103 + (_e98 / _e103)));
                    bool _e108 = (_e107 == _e103);
                    if (_e108) {
                        phi_169_ = 0;
                    } else {
                        phi_169_ = (_e101 + 1);
                    }
                    int _e111 = phi_169_;
                    phi_151_ = _e111;
                    phi_154_ = _e107;
                    phi_171_ = (_e108 ? false : true);
                } else {
                    phi_151_ = 0;
                    phi_154_ = 0.0;
                    phi_171_ = false;
                }
                int _e114 = phi_151_;
                float _e116 = phi_154_;
                bool _e118 = phi_171_;
                continue;
            }
            float _e628 = local;
            phi_176_ = _e628;
        }
        float _e121 = phi_176_;
        float _e123 = ((_e86 > _e91) ? _e86 : _e91);
        phi_582_ = ((_e121 + ((_e123 < 0.0) ? _e123 : 0.0)) - _e80);
    } else {
        if ((_e50 < 1.5)) {
            if ((_e42 <= 0.0)) {
                phi_295_ = 0.0;
                phi_296_ = true;
            } else {
                bool _e130 = (_e47 <= 0.0);
                if (_e130) {
                    phi_294_ = 0.0;
                } else {
                    float _e131 = (_e35.x / _e42);
                    float _e132 = (_e35.y / _e47);
                    float _e135 = ((_e131 * _e131) + (_e132 * _e132));
                    if ((_e135 <= 0.0)) {
                        phi_239_ = 0.0;
                    } else {
                        phi_213_ = 0;
                        phi_216_ = _e135;
                        bool loop_init_1 = true;
                        while(true) {
                            if (!loop_init_1) {
                                phi_213_ = phi_214_;
                                phi_216_ = phi_217_;
                                if (!(phi_234_)) {
                                    break;
                                }
                            }
                            loop_init_1 = false;
                            int _e138 = phi_213_;
                            float _e140 = phi_216_;
                            local_1 = _e140;
                            if ((_e138 < 20)) {
                                float _e144 = (0.5 * (_e140 + (_e135 / _e140)));
                                bool _e145 = (_e144 == _e140);
                                if (_e145) {
                                    phi_232_ = 0;
                                } else {
                                    phi_232_ = (_e138 + 1);
                                }
                                int _e148 = phi_232_;
                                phi_214_ = _e148;
                                phi_217_ = _e144;
                                phi_234_ = (_e145 ? false : true);
                            } else {
                                phi_214_ = 0;
                                phi_217_ = 0.0;
                                phi_234_ = false;
                            }
                            int _e151 = phi_214_;
                            float _e153 = phi_217_;
                            bool _e155 = phi_234_;
                            continue;
                        }
                        float _e637 = local_1;
                        phi_239_ = _e637;
                    }
                    float _e158 = phi_239_;
                    float _e160 = (_e35.x / (_e42 * _e42));
                    float _e162 = (_e35.y / (_e47 * _e47));
                    float _e165 = ((_e160 * _e160) + (_e162 * _e162));
                    if ((_e165 <= 0.0)) {
                        phi_278_ = 0.0;
                    } else {
                        phi_252_ = 0;
                        phi_255_ = _e165;
                        bool loop_init_2 = true;
                        while(true) {
                            if (!loop_init_2) {
                                phi_252_ = phi_253_;
                                phi_255_ = phi_256_;
                                if (!(phi_273_)) {
                                    break;
                                }
                            }
                            loop_init_2 = false;
                            int _e168 = phi_252_;
                            float _e170 = phi_255_;
                            local_2 = _e170;
                            if ((_e168 < 20)) {
                                float _e174 = (0.5 * (_e170 + (_e165 / _e170)));
                                bool _e175 = (_e174 == _e170);
                                if (_e175) {
                                    phi_271_ = 0;
                                } else {
                                    phi_271_ = (_e168 + 1);
                                }
                                int _e178 = phi_271_;
                                phi_253_ = _e178;
                                phi_256_ = _e174;
                                phi_273_ = (_e175 ? false : true);
                            } else {
                                phi_253_ = 0;
                                phi_256_ = 0.0;
                                phi_273_ = false;
                            }
                            int _e181 = phi_253_;
                            float _e183 = phi_256_;
                            bool _e185 = phi_273_;
                            continue;
                        }
                        float _e646 = local_2;
                        phi_278_ = _e646;
                    }
                    float _e188 = phi_278_;
                    if ((_e188 <= 0.0)) {
                        if ((_e42 < _e47)) {
                            phi_289_ = (_e41 * -0.5);
                        } else {
                            phi_289_ = (_e46 * -0.5);
                        }
                        float _e194 = phi_289_;
                        phi_293_ = _e194;
                    } else {
                        phi_293_ = ((_e158 * (_e158 - 1.0)) / _e188);
                    }
                    float _e199 = phi_293_;
                    phi_294_ = _e199;
                }
                float _e201 = phi_294_;
                phi_295_ = _e201;
                phi_296_ = _e130;
            }
            float _e203 = phi_295_;
            bool _e205 = phi_296_;
            if (_e205) {
                float _e208 = ((_e35.x * _e35.x) + (_e35.y * _e35.y));
                if ((_e208 <= 0.0)) {
                    phi_334_ = 0.0;
                } else {
                    phi_308_ = 0;
                    phi_311_ = _e208;
                    bool loop_init_3 = true;
                    while(true) {
                        if (!loop_init_3) {
                            phi_308_ = phi_309_;
                            phi_311_ = phi_312_;
                            if (!(phi_329_)) {
                                break;
                            }
                        }
                        loop_init_3 = false;
                        int _e211 = phi_308_;
                        float _e213 = phi_311_;
                        local_3 = _e213;
                        if ((_e211 < 20)) {
                            float _e217 = (0.5 * (_e213 + (_e208 / _e213)));
                            bool _e218 = (_e217 == _e213);
                            if (_e218) {
                                phi_327_ = 0;
                            } else {
                                phi_327_ = (_e211 + 1);
                            }
                            int _e221 = phi_327_;
                            phi_309_ = _e221;
                            phi_312_ = _e217;
                            phi_329_ = (_e218 ? false : true);
                        } else {
                            phi_309_ = 0;
                            phi_312_ = 0.0;
                            phi_329_ = false;
                        }
                        int _e224 = phi_309_;
                        float _e226 = phi_312_;
                        bool _e228 = phi_329_;
                        continue;
                    }
                    float _e660 = local_3;
                    phi_334_ = _e660;
                }
                float _e231 = phi_334_;
                phi_335_ = _e231;
            } else {
                phi_335_ = _e203;
            }
            float _e233 = phi_335_;
            phi_581_ = _e233;
        } else {
            float _e237 = u.data.wedge[0u];
            float _e241 = u.data.wedge[1u];
            float _e244 = ((_e35.x * _e237) - (_e35.y * _e241));
            float _e247 = ((_e35.x * _e241) + (_e35.y * _e237));
            if ((_e50 < 2.5)) {
                float _e250 = ((_e42 < _e47) ? _e42 : _e47);
                float _e254 = u.data.wedge[2u];
                float _e258 = u.data.wedge[3u];
                if ((_e244 < 0.0)) {
                    phi_370_ = -(_e244);
                } else {
                    phi_370_ = _e244;
                }
                float _e262 = phi_370_;
                float _e265 = ((_e262 * _e262) + (_e247 * _e247));
                if ((_e265 <= 0.0)) {
                    phi_405_ = 0.0;
                } else {
                    phi_379_ = 0;
                    phi_382_ = _e265;
                    bool loop_init_4 = true;
                    while(true) {
                        if (!loop_init_4) {
                            phi_379_ = phi_380_;
                            phi_382_ = phi_383_;
                            if (!(phi_400_)) {
                                break;
                            }
                        }
                        loop_init_4 = false;
                        int _e268 = phi_379_;
                        float _e270 = phi_382_;
                        local_4 = _e270;
                        if ((_e268 < 20)) {
                            float _e274 = (0.5 * (_e270 + (_e265 / _e270)));
                            bool _e275 = (_e274 == _e270);
                            if (_e275) {
                                phi_398_ = 0;
                            } else {
                                phi_398_ = (_e268 + 1);
                            }
                            int _e278 = phi_398_;
                            phi_380_ = _e278;
                            phi_383_ = _e274;
                            phi_400_ = (_e275 ? false : true);
                        } else {
                            phi_380_ = 0;
                            phi_383_ = 0.0;
                            phi_400_ = false;
                        }
                        int _e281 = phi_380_;
                        float _e283 = phi_383_;
                        bool _e285 = phi_400_;
                        continue;
                    }
                    float _e671 = local_4;
                    phi_405_ = _e671;
                }
                float _e288 = phi_405_;
                float _e289 = (_e288 - _e250);
                float _e292 = ((_e262 * _e254) + (_e247 * _e258));
                if ((_e292 < 0.0)) {
                    phi_419_ = 0.0;
                } else {
                    phi_419_ = ((_e292 > _e250) ? _e250 : _e292);
                }
                float _e297 = phi_419_;
                float _e299 = (_e262 - (_e254 * _e297));
                float _e301 = (_e247 - (_e258 * _e297));
                float _e304 = ((_e299 * _e299) + (_e301 * _e301));
                if ((_e304 <= 0.0)) {
                    phi_458_ = 0.0;
                } else {
                    phi_432_ = 0;
                    phi_435_ = _e304;
                    bool loop_init_5 = true;
                    while(true) {
                        if (!loop_init_5) {
                            phi_432_ = phi_433_;
                            phi_435_ = phi_436_;
                            if (!(phi_453_)) {
                                break;
                            }
                        }
                        loop_init_5 = false;
                        int _e307 = phi_432_;
                        float _e309 = phi_435_;
                        local_5 = _e309;
                        if ((_e307 < 20)) {
                            float _e313 = (0.5 * (_e309 + (_e304 / _e309)));
                            bool _e314 = (_e313 == _e309);
                            if (_e314) {
                                phi_451_ = 0;
                            } else {
                                phi_451_ = (_e307 + 1);
                            }
                            int _e317 = phi_451_;
                            phi_433_ = _e317;
                            phi_436_ = _e313;
                            phi_453_ = (_e314 ? false : true);
                        } else {
                            phi_433_ = 0;
                            phi_436_ = 0.0;
                            phi_453_ = false;
                        }
                        int _e320 = phi_433_;
                        float _e322 = phi_436_;
                        bool _e324 = phi_453_;
                        continue;
                    }
                    float _e681 = local_5;
                    phi_458_ = _e681;
                }
                float _e327 = phi_458_;
                if ((((_e258 * _e262) - (_e254 * _e247)) > 0.0)) {
                    phi_467_ = _e327;
                } else {
                    phi_467_ = -(_e327);
                }
                float _e334 = phi_467_;
                phi_580_ = ((_e289 > _e334) ? _e289 : _e334);
            } else {
                float _e340 = u.data.wedge[2u];
                float _e344 = u.data.wedge[3u];
                float _e348 = u.data.arc[0u];
                float _e352 = u.data.arc[1u];
                if ((_e244 < 0.0)) {
                    phi_490_ = -(_e244);
                } else {
                    phi_490_ = _e244;
                }
                float _e356 = phi_490_;
                if (((_e344 * _e356) <= (_e340 * _e247))) {
                    float _e362 = ((_e356 * _e356) + (_e247 * _e247));
                    if ((_e362 <= 0.0)) {
                        phi_531_ = 0.0;
                    } else {
                        phi_505_ = 0;
                        phi_508_ = _e362;
                        bool loop_init_6 = true;
                        while(true) {
                            if (!loop_init_6) {
                                phi_505_ = phi_506_;
                                phi_508_ = phi_509_;
                                if (!(phi_526_)) {
                                    break;
                                }
                            }
                            loop_init_6 = false;
                            int _e365 = phi_505_;
                            float _e367 = phi_508_;
                            local_6 = _e367;
                            if ((_e365 < 20)) {
                                float _e371 = (0.5 * (_e367 + (_e362 / _e367)));
                                bool _e372 = (_e371 == _e367);
                                if (_e372) {
                                    phi_524_ = 0;
                                } else {
                                    phi_524_ = (_e365 + 1);
                                }
                                int _e375 = phi_524_;
                                phi_506_ = _e375;
                                phi_509_ = _e371;
                                phi_526_ = (_e372 ? false : true);
                            } else {
                                phi_506_ = 0;
                                phi_509_ = 0.0;
                                phi_526_ = false;
                            }
                            int _e378 = phi_506_;
                            float _e380 = phi_509_;
                            bool _e382 = phi_526_;
                            continue;
                        }
                        float _e692 = local_6;
                        phi_531_ = _e692;
                    }
                    float _e385 = phi_531_;
                    float _e386 = (_e385 - _e348);
                    if ((_e386 < 0.0)) {
                        phi_538_ = -(_e386);
                    } else {
                        phi_538_ = _e386;
                    }
                    float _e390 = phi_538_;
                    phi_578_ = _e390;
                } else {
                    float _e393 = (_e356 - (_e340 * _e348));
                    float _e394 = (_e247 - (_e344 * _e348));
                    float _e397 = ((_e393 * _e393) + (_e394 * _e394));
                    if ((_e397 <= 0.0)) {
                        phi_577_ = 0.0;
                    } else {
                        phi_551_ = 0;
                        phi_554_ = _e397;
                        bool loop_init_7 = true;
                        while(true) {
                            if (!loop_init_7) {
                                phi_551_ = phi_552_;
                                phi_554_ = phi_555_;
                                if (!(phi_572_)) {
                                    break;
                                }
                            }
                            loop_init_7 = false;
                            int _e400 = phi_551_;
                            float _e402 = phi_554_;
                            local_7 = _e402;
                            if ((_e400 < 20)) {
                                float _e406 = (0.5 * (_e402 + (_e397 / _e402)));
                                bool _e407 = (_e406 == _e402);
                                if (_e407) {
                                    phi_570_ = 0;
                                } else {
                                    phi_570_ = (_e400 + 1);
                                }
                                int _e410 = phi_570_;
                                phi_552_ = _e410;
                                phi_555_ = _e406;
                                phi_572_ = (_e407 ? false : true);
                            } else {
                                phi_552_ = 0;
                                phi_555_ = 0.0;
                                phi_572_ = false;
                            }
                            int _e413 = phi_552_;
                            float _e415 = phi_555_;
                            bool _e417 = phi_572_;
                            continue;
                        }
                        float _e702 = local_7;
                        phi_577_ = _e702;
                    }
                    float _e420 = phi_577_;
                    phi_578_ = _e420;
                }
                float _e422 = phi_578_;
                phi_580_ = (_e422 - _e352);
            }
            float _e425 = phi_580_;
            phi_581_ = _e425;
        }
        float _e427 = phi_581_;
        phi_582_ = _e427;
    }
    float _e429 = phi_582_;
    float _e432 = u.data.inset;
    float _e433 = (_e429 + _e432);
    float _e436 = u.data.gradient_kind;
    if ((_e436 < 0.5)) {
        phi_699_ = 0.0;
    } else {
        if ((_e436 < 1.5)) {
            float _e442 = u.data.gradient[0u];
            float _e446 = u.data.gradient[1u];
            float _e450 = u.data.gradient[2u];
            float _e454 = u.data.gradient[3u];
            float _e455 = (_e450 - _e442);
            float _e456 = (_e454 - _e446);
            float _e459 = ((_e455 * _e455) + (_e456 * _e456));
            if ((_e459 <= 0.0)) {
                phi_635_ = 0.0;
            } else {
                float _e466 = ((((_e35.x - _e442) * _e455) + ((_e35.y - _e446) * _e456)) / _e459);
                if ((_e466 < 0.0)) {
                    phi_634_ = 0.0;
                } else {
                    phi_634_ = ((_e466 > 1.0) ? 1.0 : _e466);
                }
                float _e471 = phi_634_;
                phi_635_ = _e471;
            }
            float _e473 = phi_635_;
            phi_698_ = _e473;
        } else {
            float _e477 = u.data.gradient[0u];
            float _e481 = u.data.gradient[1u];
            float _e485 = u.data.gradient[2u];
            if ((_e485 <= 0.0)) {
                phi_697_ = 1.0;
            } else {
                float _e487 = (_e35.x - _e477);
                float _e488 = (_e35.y - _e481);
                float _e491 = ((_e487 * _e487) + (_e488 * _e488));
                if ((_e491 <= 0.0)) {
                    phi_685_ = 0.0;
                } else {
                    phi_659_ = 0;
                    phi_662_ = _e491;
                    bool loop_init_8 = true;
                    while(true) {
                        if (!loop_init_8) {
                            phi_659_ = phi_660_;
                            phi_662_ = phi_663_;
                            if (!(phi_680_)) {
                                break;
                            }
                        }
                        loop_init_8 = false;
                        int _e494 = phi_659_;
                        float _e496 = phi_662_;
                        local_8 = _e496;
                        if ((_e494 < 20)) {
                            float _e500 = (0.5 * (_e496 + (_e491 / _e496)));
                            bool _e501 = (_e500 == _e496);
                            if (_e501) {
                                phi_678_ = 0;
                            } else {
                                phi_678_ = (_e494 + 1);
                            }
                            int _e504 = phi_678_;
                            phi_660_ = _e504;
                            phi_663_ = _e500;
                            phi_680_ = (_e501 ? false : true);
                        } else {
                            phi_660_ = 0;
                            phi_663_ = 0.0;
                            phi_680_ = false;
                        }
                        int _e507 = phi_660_;
                        float _e509 = phi_663_;
                        bool _e511 = phi_680_;
                        continue;
                    }
                    float _e717 = local_8;
                    phi_685_ = _e717;
                }
                float _e514 = phi_685_;
                float _e515 = (_e514 / _e485);
                if ((_e515 < 0.0)) {
                    phi_696_ = 0.0;
                } else {
                    phi_696_ = ((_e515 > 1.0) ? 1.0 : _e515);
                }
                float _e520 = phi_696_;
                phi_697_ = _e520;
            }
            float _e522 = phi_697_;
            phi_698_ = _e522;
        }
        float _e524 = phi_698_;
        phi_699_ = _e524;
    }
    float _e526 = phi_699_;
    vec4 _e529 = u.data.fill_color;
    vec4 _e532 = u.data.fill_color1;
    float _e555 = u.data.pixel_scale;
    float _e557 = (0.5 - (_e433 * _e555));
    if ((_e557 < 0.0)) {
        phi_743_ = 0.0;
    } else {
        phi_743_ = ((_e557 > 1.0) ? 1.0 : _e557);
    }
    float _e562 = phi_743_;
    float _e566 = u.data.stroke_width;
    if ((_e566 > 0.0)) {
        if ((_e433 < 0.0)) {
            phi_759_ = -(_e433);
        } else {
            phi_759_ = _e433;
        }
        float _e572 = phi_759_;
        float _e575 = (0.5 - ((_e572 - (_e566 * 0.5)) * _e555));
        if ((_e575 < 0.0)) {
            phi_772_ = 0.0;
        } else {
            phi_772_ = ((_e575 > 1.0) ? 1.0 : _e575);
        }
        float _e580 = phi_772_;
        float _e584 = u.data.stroke_color[3u];
        phi_777_ = (_e580 * _e584);
    } else {
        phi_777_ = 0.0;
    }
    float _e587 = phi_777_;
    float _e589 = ((_e562 * (_e529.w + ((_e532.w - _e529.w) * _e526))) * (1.0 - _e587));
    float _e590 = (_e587 + _e589);
    if ((_e590 <= 0.0)) {
        output_ = vec4(0.0, 0.0, 0.0, 0.0);
    } else {
        float _e595 = u.data.stroke_color[0u];
        float _e603 = u.data.stroke_color[1u];
        float _e611 = u.data.stroke_color[2u];
        output_ = vec4((((_e595 * _e587) + ((_e529.x + ((_e532.x - _e529.x) * _e526)) * _e589)) / _e590), (((_e603 * _e587) + ((_e529.y + ((_e532.y - _e529.y) * _e526)) * _e589)) / _e590), (((_e611 * _e587) + ((_e529.z + ((_e532.z - _e529.z) * _e526)) * _e589)) / _e590), _e590);
    }
    return;
}

void main() {
    vec2 v_local = _vs2fs_location0;
    v_local_1 = v_local;
    function();
    vec4 _e3 = output_;
    _fs2p_location0 = _e3;
    return;
}

